require File.dirname(__FILE__) + "/Backend"
require File.dirname(__FILE__) + "/Behavior"
require File.dirname(__FILE__) + "/Nginx"
require File.dirname(__FILE__) + "/Signer"
class Vcl
  attr_reader :host_collection, :resp, :kpis
  @@elb_count = 0
  @@nginx_array = Array.new

  def initialize(id, resp)
    @id = id
    @resp = resp.distribution
    @host_name = resp.distribution.domain_name
  end

  def extract_initial(str)
    str.slice!(/[.].*/)
    str
  end

  def self.nginx_array
    p @@nginx_array
  end

  def elb?(host)
    info = TCPSocket.gethostbyname("#{host}")
    return info.size>=5 ? true : false
  end

  def genVcl

    @host_collection = Array.new
    @host_collection.push(@host_name)
    @resp.distribution_config.aliases.items.each do |aliase|
      @host_collection.push(aliase)
    end

    # ディストリビューションのidを指定してディストリビューションの情報を取ってくる
    # begin
    #   resp = cf.get_distribution_config({
    #     id: @id
    #   })
    # rescue AWS::CloudFront::Errors::ServiceSrror
    #   puts '[ERROR] '+ $!.message
    #   exit 1
    # end


    # vclに書き出すコードの配列を宣言
    entire_code = Array.new
    # vclのバージョンを指定
    # entire_code << "vcl 4.0;"


    # entire_nginx_code = Array.new
    # entire_nginx_code << "worker_processes  auto;"
    # entire_nginx_code << "events {"
    # entire_nginx_code << "  worker_connections  1024;"
    # entire_nginx_code << "}"
    # entire_nginx_code << "http {"
    # entire_nginx_code << "  include       mime.types;"
    # entire_nginx_code << "  default_type  application/octet-stream;"
    # entire_nginx_code << "  keepalive_timeout  65;"
    # entire_nginx_code << "  server_tokens off;"


    # Backend情報を格納する配列を宣言
    backend_array = Array.new
    @resp.distribution_config.origins.items.each_with_index do |origin, index|
      if (elb?(origin.domain_name))
        @@elb_count += 1
        @@nginx_array[@@elb_count-1] = Nginx.new(origin.domain_name, 50000+@@elb_count)
        @@nginx_array[@@elb_count-1].store_code_for_nginx
        # entire_nginx_code.concat(nginx_array[@@elb_count-1].output_array)
      end
      # CFのOriginの数だけbackend配列に格納
      backend_array[index] = Backend.new(origin, elb?(origin.domain_name), @@elb_count)
      # Backendのvcl用コードを生成
      backend_array[index].store_code_for_declar_backend
      # entire_codeに格納
      entire_code.concat(backend_array[index].output_array)
    end

    # entire_nginx_code << "}"

    # Bahavior情報を格納する配列を宣言
    behavior_array = Array.new
    # CFのbehaviorのDefault Behavior以外をbehavior配列に格納
    @resp.distribution_config.cache_behaviors.items.each_with_index do |behavior, index|
      behavior_array[index] = AdditionBehavior.new(behavior)
    end
    # CFのbehaviorのDefault Behaviorをbehavior配列に格納
    behavior_array[behavior_array.length] = DefaultBehavior.new(@resp.distribution_config.default_cache_behavior)

    # Behaviorのvcl用コードを生成
    behavior_array.each_with_index do |behavior, index|
      behavior_array[index].store_code_for_recv
      behavior_array[index].store_code_for_hash
      behavior_array[index].store_code_for_miss
      behavior_array[index].store_code_for_backend_resp
    end

    # vcl_recv箇所をentire_codeに格納
    entire_code << "sub #{extract_initial(@host_name)}_vcl_recv {"
    behavior_array.each_with_index do |behavior, index|
      entire_code.concat(behavior.output_array_for_recv)
    end
    entire_code << "}"

    # vcl_hash箇所をentire_codeに格納
    entire_code << "sub #{extract_initial(@host_name)}_vcl_hash {"
    behavior_array.each_with_index do |behavior, index|
      entire_code.concat(behavior.output_array_for_hash)
    end
    entire_code << "}"

    entire_code << "sub #{extract_initial(@host_name)}_vcl_miss {"
    behavior_array.each_with_index do |behavior, index|
      entire_code.concat(behavior.output_array_for_miss)
    end
    entire_code << "}"

    # vcl_backend_response箇所をentire_codeに格納
    entire_code << "sub #{extract_initial(@host_name)}_vcl_backend_response {"

    ############ error pageあとでクラスをわける
    @resp.distribution_config.custom_error_responses.items.each do |custom_error|
      entire_code << "  if(beresp.status == #{custom_error.error_code}){"
      if(custom_error.error_caching_min_ttl>300)
        entire_code << "    set beresp.ttl = #{custom_error.error_caching_min_ttl}s;"
      else
        entire_code << "    set beresp.ttl = 300s;"
      end
      entire_code << "    return(deliver);"
      entire_code << "  }"
    end

    entire_code << "  if((beresp.status == 400) || (beresp.status == 403) || (beresp.status == 404) || (beresp.status == 405) || (beresp.status == 414) || (beresp.status == 500) || (beresp.status == 501) || (beresp.status == 502) || (beresp.status == 503) || (beresp.status == 504)){"
    entire_code << "    set beresp.ttl = 300s;"
    entire_code << "    return(deliver);"
    entire_code << "  }"


    behavior_array.each_with_index do |behavior, index|
      entire_code.concat(behavior.output_array_for_backend_resp)
    end
    entire_code << "}"


    # vcl_hit箇所をentire_codeに格納
    entire_code << "sub #{extract_initial(@host_name)}_vcl_hit {"
    # vcl_deliverでは参照できないobj.ttlの値を一時的に保存する
    entire_code << "  set req.http.Remain-ttl-tmp = obj.ttl;"
    entire_code << "}"

    # vcl_deliverをentire_codeに格納
    entire_code << "sub #{extract_initial(@host_name)}_vcl_deliver {"
    entire_code << "  if(obj.hits > 0){"
    # キャッシュが有る場合はX-CacheにHitを挿入
    entire_code << "    set resp.http.X-Cache = \"Hit from varnish\";"
    # X-Remain-TTLに残りのキャッシュ保持期間を格納
    entire_code << "    set resp.http.X-Remain-TTL = req.http.Remain-ttl-tmp;"
    # 一時的に保存したデータを削除
    entire_code << "    unset req.http.Remain-ttl-tmp;"
    entire_code << "  }else{"
    # キャッシュが無い場合はX-CacheにMissを挿入
    entire_code << "    set resp.http.X-Cache = \"Miss from varnish\";"
    entire_code << "  }"
    entire_code << "}"

    # コードをvclに書き出す
    File.open("/etc/varnish/#{extract_initial(@host_name)}.vcl", 'w') do |file|
      for entire_code_line in entire_code do
        file.puts entire_code_line
      end
    end

    # File.open('/etc/nginx/nginx.conf', 'w') do |file|
    #   for entire_code_line in entire_nginx_code do
    #     file.puts entire_code_line
    #   end
    # end
  end

  def getKeyPiarIds
    @kpis = Array.new
    @resp.active_trusted_signers.items.each do |signer|
      signer.key_pair_ids.items.each do |kpi|
        @kpis.push(kpi)
      end
    end
    @kpis
  end
end
