class Nginx
  attr_reader :output_array
  def initialize(host, port)
    @host = host
    @port = port
    @output_array = Array.new
  end

  def store_code_for_nginx
    @output_array << "  server {"
    @output_array << "    listen localhost:#{@port};"
    @output_array << "    location / {"
    @output_array << "      resolver 8.8.8.8;"
    @output_array << "      set $backend_host \"#{@host}\";"
    @output_array << "      proxy_pass http://$backend_host;"
    @output_array << "      proxy_set_header Host $http_host;"
    @output_array << "    }"
    @output_array << "  }"
  end

end
