require 'nokogiri'
require 'open-uri'
require 'open_uri_redirections'

##
# The DuckDuckGo module.
module DuckDuckGo

  ##
  # The suffix for the URL that we visit when querying DuckDuckGo.
  RESOURCE_URL = 'https://duckduckgo.com/html/?q='

  ##
  # Searches DuckDuckGo for the given query string. This function returns an array of SearchResults.
  #
  # @param [Hash] hash a hash containing the query string and possibly other configuration settings.
  # @raise [Exception] if there is an error scraping DuckDuckGo for the search results.
  def self.search(hash)

    results = []

    raise 'Hash does not contain a query string.' if hash[:query].nil?
    begin
      html = open("#{RESOURCE_URL}#{CGI.escape(hash[:query])}")
    rescue OpenURI::HTTPError => e
      response = e.io
      if response.status&.first&.to_i == 403
        raise "Likely too many connections, thrown 403 forbidden error"
      else
        raise
      end
    end

    document = Nokogiri::HTML(html)

    document_results = document.css('#links .result')

    # Limit results before running through the filter
    document_results = document_results.first(hash[:pre_filter_limit]).compact if hash[:pre_filter_limit].present?

    document_results.each do |result|
      title_element = result.css('.result__a').first
      raise 'Could not find result link element!' if title_element.nil?

      title = title_element.text
      raise 'Could not find result title!' if title.nil?

      break if title.squish == "No results."

      uri = title_element['href']&.gsub(/\/l\/\?kh=-1&uddg=/, '')
      raise 'Could not find result URL!' if uri.nil?
      uri = URI.decode(uri || '')

      description_element = result.css('.result__snippet').first
      if description_element.present?
        description = description_element.text
        raise 'Could not find result description!' if description.nil?
      end

      results << SearchResult.new(uri, title, description)
    end

    # Yield block to run a custom filter before putting it through the
    # expensive redirection lookup
    if block_given?
      results = results.select do |result|
        yield result
      end
    end

    # Limit results
    if hash[:limit].present?
      results = results.first(hash[:limit]).compact
    end

    results.each do |result|
      # Attempt to follow redirects, since DuckDuckGo often aggregates search results from Yahoo.
      begin
        # Avoid downloading PDFs, it takes a while
        next if result.uri =~ /\.pdf$/

        final_uri = open(result.uri, :allow_redirections => :all, :read_timeout => 5).base_uri.to_s
        result.uri = final_uri
      rescue
      end
    end

    return results
  end
end