module TeamcityHelper
  module Misc
    class JsonClient
      def initialize(options={})
        @options = options
      end

      def headers(type)
        accept = ""
        content_type = ""
        case type
        when "xml"
          accept = "application/xml; charset=utf-8"
          content_type = "application/xml"
        when "json"
          accept = "application/json; charset=utf-8"
          content_type = "application/json"
        when "text"
          accept = "text/plain"
          content_type = "text/plain"
        end
        return accept, content_type
      end

      def get(path, header_type)
        curl = Curl::Easy.new(path)
        accept, content_type = headers(header_type)
        curl.http_auth_types = @options[:auth_type]
        curl.username = @options[:username]
        curl.password = @options[:password]
        curl.headers["Accept"] = accept
        curl.headers["Content-Type"] = content_type
        curl.perform
        return curl.body_str
      end

      def post(path, header_type, content)
        curl = Curl::Easy.new(path)
        accept, content_type = headers(header_type)
        curl.username = @options[:username]
        curl.password = @options[:password]
        curl.headers["Accept"] = accept
        curl.headers["Content-Type"] = content_type
        curl.post_body = content
        curl.http_post
        return curl.body_str
      end
    end

    def client
      JsonClient.new(
        username: config.username,
        password: config.password,
        auth_type: :basic
      )
    end
  end
end
