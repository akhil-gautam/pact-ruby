require 'pact/retry'
require 'pact/hal/authorization_header_redactor'
require 'net/http'
require 'rack'

module Pact
  module Hal
    class HttpClient
      attr_accessor :username, :password, :verbose, :token

      def initialize options
        @username = options[:username]
        @password = options[:password]
        @verbose = options[:verbose]
        @token = options[:token]
      end

      def get href, params = {}, headers = {}
        uri = URI(href)
        if params && params.any?
          existing_params = Rack::Utils.parse_nested_query(uri.query)
          uri.query = Rack::Utils.build_nested_query(existing_params.merge(params))
        end
        perform_request(create_request(uri, 'Get', nil, headers), uri)
      end

      def put href, body = nil, headers = {}
        uri = URI(href)
        perform_request(create_request(uri, 'Put', body, headers), uri)
      end

      def post href, body = nil, headers = {}
        uri = URI(href)
        perform_request(create_request(uri, 'Post', body, headers), uri)
      end

      def create_request uri, http_method, body = nil, headers = {}
        request = Net::HTTP.const_get(http_method).new(uri.request_uri)
        headers.each do | key, value |
          request[key] = value
        end
        request.body = body if body
        request.basic_auth username, password if username
        request['Authorization'] = "Bearer #{token}" if token
        request
      end

      def perform_request request, uri
        response = Retry.until_true do
          http = Net::HTTP.new(uri.host, uri.port, :ENV)
          http.set_debug_output(output_stream) if verbose || ENV['VERBOSE'] == 'true'
          http.use_ssl = (uri.scheme == 'https')
          http.ca_file = ENV['SSL_CERT_FILE'] if ENV['SSL_CERT_FILE'] && ENV['SSL_CERT_FILE'] != ''
          http.ca_path = ENV['SSL_CERT_DIR'] if ENV['SSL_CERT_DIR'] && ENV['SSL_CERT_DIR'] != ''
          http.start do |http|
            http.request request
          end
        end
        Response.new(response)
      end

      def output_stream
        AuthorizationHeaderRedactor.new(Pact.configuration.output_stream)
      end

      class Response < SimpleDelegator
        def body
          bod = raw_body
          if bod && bod != ''
            JSON.parse(bod)
          else
            nil
          end
        end

        def raw_body
          __getobj__().body
        end

        def status
          code.to_i
        end

        def success?
          __getobj__().code.start_with?("2")
        end

        def json?
          self['content-type'] && self['content-type'] =~ /json/
        end
      end
    end
  end
end
