# -*- coding: utf-8 -*-
require "cfcloner/version"
require "aws-sdk"
require "socket"
require "../../id_cf"
require "../../host.rb"
# require File.dirname(__FILE__) + "/Backend"
# require File.dirname(__FILE__) + "/Behavior"
# require File.dirname(__FILE__) + "/Nginx"
require File.dirname(__FILE__) + "/Vcl"

def extract_initial(str)
  str.slice!(/[.].*/)
  return str
end

module Cfcloner

  entire_code = Array.new
  host_collection = Array.new($id_cf.size).map{[]}
  kpis = Array.new

  # CloudFrontのインスタンスを生成
  cf = Aws::CloudFront::Client.new(
    region: 'ap-northeast-1'
  )

  vcls = Array.new
  $id_cf.each_with_index do |id, index|
    begin
      resp = cf.get_distribution({
        id: id
      })
    rescue AWS::CloudFront::Errors::ServiceSrror
      puts '[ERROR] '+ $!.message
      exit 1
    end

    vcls[index] = Vcl.new(id, resp)
    vcls[index].genVcl
    # Combine with active Key Pair IDs in each host.
    kpis.concat(vcls[index].getKeyPiarIds)
    vcls[index].host_collection.each do |host_name|
      host_collection[index].push(host_name)
    end
  end


  entire_code << "vcl 4.0;"
  host_collection.each do |host_name|
    entire_code << "include \"#{extract_initial(host_name[0])}.vcl\";"
  end

  kpis = kpis.uniq
  unless kpis.empty?
    # If Key Pair IDs is exist, output the vcl file for PrivateContent, and then include this.
    signer = Signer.new(kpis)
    File.open('/etc/varnish/signature.vcl', 'w') do |file|
      file.puts signer.store_code
    end
    entire_code << "include \"signature.vcl\";"
  end

  entire_code << "sub vcl_recv {"
  host_collection.each_with_index do |host_name, index|
    entire_code << "  if(req.http.Host == "
    entire_code[entire_code.length-1] += "\"#{extract_initial(host_name[0])}-#{$varnish_num}.#{$varnish_host}\" || req.http.Host == "
    host_name.each_with_index do |host, index2|
      entire_code[entire_code.length-1] += "\"#{host}\""
      entire_code[entire_code.length-1] += (index2 != (host_name.size-1))? " || req.http.Host == " : ""
    end
    entire_code[entire_code.length-1] += "){"
    entire_code << "    call #{extract_initial(host_name[0])}_vcl_recv;"
    entire_code << "  }"
  end
  entire_code << "}"


  entire_code << "sub vcl_hash {"
  host_collection.each_with_index do |host_name, index|
    entire_code << "  if(req.http.Host == "
    entire_code[entire_code.length-1] += "\"#{extract_initial(host_name[0])}-#{$varnish_num}.#{$varnish_host}\" || req.http.Host == "
    host_name.each_with_index do |host, index2|
      entire_code[entire_code.length-1] += "\"#{host}\""
      entire_code[entire_code.length-1] += (index2 != (host_name.size-1))? " || req.http.Host == " : ""
    end
    entire_code[entire_code.length-1] += "){"
    entire_code << "    call #{extract_initial(host_name[0])}_vcl_hash;"
    entire_code << "  }"
  end
  entire_code << "}"

  entire_code << "sub vcl_miss {"
  host_collection.each_with_index do |host_name, index|
    entire_code << "  if(req.http.Host == "
    entire_code[entire_code.length-1] += "\"#{extract_initial(host_name[0])}-#{$varnish_num}.#{$varnish_host}\" || req.http.Host == "
    host_name.each_with_index do |host, index2|
      entire_code[entire_code.length-1] += "\"#{host}\""
      entire_code[entire_code.length-1] += (index2 != (host_name.size-1))? " || req.http.Host == " : ""
    end
    entire_code[entire_code.length-1] += "){"
    entire_code << "    call #{extract_initial(host_name[0])}_vcl_miss;"
    entire_code << "  }"
  end
  entire_code << "}"

  entire_code << "sub vcl_backend_response {"
  host_collection.each_with_index do |host_name, index|
    entire_code << "  if(bereq.http.Host == "
    entire_code[entire_code.length-1] += "\"#{extract_initial(host_name[0])}-#{$varnish_num}.#{$varnish_host}\" || bereq.http.Host == "
    host_name.each_with_index do |host, index2|
      entire_code[entire_code.length-1] += "\"#{host}\""
      entire_code[entire_code.length-1] += (index2 != (host_name.size-1))? " || bereq.http.Host == " : ""
    end
    entire_code[entire_code.length-1] += "){"
    entire_code << "    call #{extract_initial(host_name[0])}_vcl_backend_response;"
    entire_code << "  }"
  end
  entire_code << "}"

  entire_code << "sub vcl_hit {"
  host_collection.each_with_index do |host_name, index|
    entire_code << "  if(req.http.Host == "
    entire_code[entire_code.length-1] += "\"#{extract_initial(host_name[0])}-#{$varnish_num}.#{$varnish_host}\" || req.http.Host == "
    host_name.each_with_index do |host, index2|
      entire_code[entire_code.length-1] += "\"#{host}\""
      entire_code[entire_code.length-1] += (index2 != (host_name.size-1))? " || req.http.Host == " : ""
    end
    entire_code[entire_code.length-1] += "){"
    entire_code << "    call #{extract_initial(host_name[0])}_vcl_hit;"
    entire_code << "  }"
  end
  entire_code << "}"

  entire_code << "sub vcl_deliver {"
  host_collection.each_with_index do |host_name, index|
    entire_code << "  if(req.http.Host == "
    entire_code[entire_code.length-1] += "\"#{extract_initial(host_name[0])}-#{$varnish_num}.#{$varnish_host}\" || req.http.Host == "
    host_name.each_with_index do |host, index2|
      entire_code[entire_code.length-1] += "\"#{host}\""
      entire_code[entire_code.length-1] += (index2 != (host_name.size-1))? " || req.http.Host == " : ""
    end
    entire_code[entire_code.length-1] += "){"
    entire_code << "    call #{extract_initial(host_name[0])}_vcl_deliver;"
    entire_code << "  }"
  end
  entire_code << "}"

  File.open("/etc/varnish/default.vcl", 'w') do |file|
    for entire_code_line in entire_code do
      file.puts entire_code_line
    end
  end




  entire_nginx_code = Array.new
  entire_nginx_code << "worker_processes  auto;"
  entire_nginx_code << "events {"
  entire_nginx_code << "  worker_connections  1024;"
  entire_nginx_code << "}"
  entire_nginx_code << "http {"
  entire_nginx_code << "  include       mime.types;"
  entire_nginx_code << "  default_type  application/octet-stream;"
  entire_nginx_code << "  keepalive_timeout  65;"
  entire_nginx_code << "  server_tokens off;"

  Vcl.nginx_array.each do |nginx|
    entire_nginx_code.concat(nginx.output_array)
  end
  entire_nginx_code << "}"

  File.open('/etc/nginx/nginx.conf', 'w') do |file|
    for entire_code_line in entire_nginx_code do
      file.puts entire_code_line
    end
  end

end
