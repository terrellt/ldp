module Ldp
  module Response
    require 'ldp/response/paging'

    ##
    # Wrap the raw Faraday respone with our LDP extensions
    def self.wrap client, raw_resp
      raw_resp.send(:extend, Ldp::Response)
      raw_resp.send(:extend, Ldp::Response::Paging) if raw_resp.has_page?
      raw_resp
    end

    ##
    # Extract the Link: headers from the HTTP resource
    def self.links response
      h = {}
      Array(response.headers["Link"]).map { |x| x.split(", ") }.flatten.inject(h) do |memo, header|
        m = header.match(/<(?<link>.*)>;\s?rel="(?<rel>[^"]+)"/)
        if m
          memo[m[:rel]] ||= []
          memo[m[:rel]] << m[:link]
        end

        memo
      end
    end
    
    def self.applied_preferences headers
      h = {}
      
      Array(headers).map { |x| x.split(",") }.flatten.inject(h) do |memo, header|
        m = header.match(/(?<key>[^=;]*)(=(?<value>[^;,]*))?(;\s*(?<params>[^,]*))?/)
        includes = (m[:params].match(/include="(?<include>[^"]+)"/)[:include] || "").split(" ")
        omits = (m[:params].match(/omit="(?<omit>[^"]+)"/)[:omit] || "").split(" ")
        memo[m[:key]] = { value: m[:value], includes: includes, omits: omits }
      end
    end

    ##
    # Is the response an LDP resource?

    def self.resource? response
      container?(response) || Array(links(response)["type"]).include?(Ldp.resource.to_s)
    end

    ##
    # Is the response an LDP container?
    def self.container? response
      [
        Ldp.basic_container, 
        Ldp.direct_container, 
        Ldp.indirect_container
      ].any? { |x| Array(links(response)["type"]).include? x.to_s }
    end
    
    ##
    # Link: headers from the HTTP response
    def links
      @links ||= Ldp::Response.links(self)
    end

    ##
    # Is the response an LDP resource?
    def resource?
      Ldp::Response.resource?(self)
    end

    ##
    # Is the response an LDP container
    def container?
      Ldp::Response.container?(self)
    end

    def preferences
      Ldp::Resource.applied_preferences(headers["Preference-Applied"])
    end
    ##
    # Get the subject for the response
    def subject
      page_subject
    end

    ##
    # Get the URI to the response
    def page_subject
      @page_subject ||= RDF::URI.new env[:url]
    end

    ##
    # Is the response paginated?
    def has_page?
      graph.has_statement? RDF::Statement.new(page_subject, RDF.type, Ldp.page)
    end

    ##
    # Get the graph for the resource (or a blank graph if there is no metadata for the resource)
    def graph
      @graph ||= begin
        graph = RDF::Graph.new

        if resource?
          RDF::Reader.for(:ttl).new(StringIO.new(body), :base_uri => page_subject) do |reader|
            reader.each_statement do |s|
              graph << s
            end
          end
        end

        graph
      end
    end

    ##
    # Extract the ETag for the resource
    def etag
      @etag ||= headers['ETag']
    end

    def etag=(val)
      @etag = val
    end

    ##
    # Extract the last modified header for the resource
    def last_modified
      @last_modified ||= headers['Last-Modified']
    end

    def last_modified=(val)
      @last_modified = val
    end

    ##
    # Extract the Link: rel="type" headers for the resource
    def types
      Array(links["type"])
    end
    
    def includes? preference
      key = Ldp.send("prefer_#{preference}") if Ldp.respond_to("prefer_#{preference}")
      key ||= preference
      preferences["return"][:includes].include?(key) || !preferences["return"][:omits].include?(key) 
    end
    
    def minimal?
      preferences["return"][:value] == "minimal"
    end
  end
end
