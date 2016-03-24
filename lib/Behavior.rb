class Behavior
  attr_reader :output_array_for_recv, :output_array_for_hash, :output_array_for_backend_resp, :output_array_for_miss
  def initialize(cache_behavior)
    @backend_name = delete_symbol(cache_behavior.target_origin_id)
    @allowed_methods = cache_behavior.allowed_methods.items
    @cached_methods = cache_behavior.allowed_methods.cached_methods.items
    @forward_headers = cache_behavior.forwarded_values.headers
    @forward_cookies = cache_behavior.forwarded_values.cookies
    @forward_query_string = cache_behavior.forwarded_values.query_string
    @min_ttl = cache_behavior.min_ttl
    @max_ttl = cache_behavior.max_ttl
    @default_ttl = cache_behavior.default_ttl
    @trusted_signers = cache_behavior.trusted_signers
    @output_array_for_recv = Array.new
    @output_array_for_backend_resp = Array.new
    @output_array_for_hash = Array.new
    @output_array_for_miss = Array.new
  end


  def store_code_for_recv
    @output_array_for_recv << "  set req.http.X-PARAMS = regsub(req.url, \"^.*(\\?.*)$\", \"\\1\");" if @trusted_signers.enabled
    ## CFのForwardQueryStringが NO だった場合，QueryStrginを削除
    @forward_query_string? "" : "#{@output_array_for_recv << "  set req.url = regsub(req.url, \"\\?.*$\", \"\");"}"
    # ALLOWED METHODS
    @output_array_for_recv << "  if("
    @allowed_methods.each_with_index do |method, index|
      @output_array_for_recv[@output_array_for_recv.length-1] += "req.method == \"#{method}\""
      # 最後の要素で無ければOR演算子を付加する
      @output_array_for_recv[@output_array_for_recv.length-1] += (index != (@allowed_methods.size-1))? " || " : ""
    end
    @output_array_for_recv[@output_array_for_recv.length-1] += "){"
    # CACHED METHODS
    @output_array_for_recv << "    if("
    @cached_methods.each_with_index do |method, index|
      @output_array_for_recv[@output_array_for_recv.length-1] += "req.method == \"#{method}\""
      # 最後の要素で無ければOR演算子を付加する
      @output_array_for_recv[@output_array_for_recv.length-1] += (index != (@cached_methods.size-1))? " || " : ""
    end
    # FORWARD HEADERS
    @output_array_for_recv[@output_array_for_recv.length-1] += "){"
    if @forward_headers.items[0] == "*"
      @output_array_for_recv << "        return (pipe);"
    end
    # FORWARD COOKIES
    case @forward_cookies.forward
    when "none"
      @output_array_for_recv << "      unset req.http.Cookie;"

    when "whitelist"
      @output_array_for_recv << "      set req.http.Cookie = \";\" + req.http.Cookie;"
      @output_array_for_recv << "      set req.http.Cookie = regsuball(req.http.Cookie, \"; +\", \";\");"
      @output_array_for_recv << "      set req.http.Cookie = regsuball(req.http.Cookie, \";("
      @forward_cookies.whitelisted_names.items.each_with_index do |cookie, index|
        @output_array_for_recv[@output_array_for_recv.length-1] += "#{cookie}"
        @output_array_for_recv[@output_array_for_recv.length-1] += (index != (@forward_cookies.whitelisted_names.quantity-1))? "|" : ""
      end
      @output_array_for_recv[@output_array_for_recv.length-1] += ")=\", \"; \\1=\");"
      @output_array_for_recv << "      set req.http.Cookie = regsuball(req.http.Cookie, \";[^ ][^;]*\", \"\");"
      @output_array_for_recv << "      set req.http.Cookie = regsuball(req.http.Cookie, \"^[; ]+|[; ]+$\", \"\");"

    when "all"
    end

    # backendをセットする
    @output_array_for_recv << "      set req.backend_hint = #{@backend_name};"
    @output_array_for_recv << "      return (hash);"
    @output_array_for_recv << "    }else{"
    @output_array_for_recv << "      return (pipe);"
    @output_array_for_recv << "    }"
    @output_array_for_recv << "  }else{"
    @output_array_for_recv << "    return (synth(405, \"Method Not Allowed\"));"
    @output_array_for_recv << "  }"
  end

  def store_code_for_backend_resp
    ## cacheがprivateではないか
    ## cacheがprivateであれば，min_ttlをセットする
    @output_array_for_backend_resp << "  if(beresp.http.cache-control ~ \"no-cache\" || beresp.http.cache-control ~ \"no-store\" || beresp.http.cache-control ~ \"private\"){"
    @output_array_for_backend_resp << "    set beresp.ttl = #{@min_ttl}s;"
    @output_array_for_backend_resp << "    return (deliver);"
    @output_array_for_backend_resp << "  }"
    @output_array_for_backend_resp << "  if((beresp.http.cache-control ~ \"max-age\") || (beresp.http.cache-control ~ \"s-maxage\") || (beresp.http.expires)){"
    ## beresp.ttlに，beresp.ttl(max-age?=>s-maxage?=>expires?=>default_ttl)がmin_ttlより小さければmin_ttlを，max_ttlより大きければmax_ttlを設定
    @output_array_for_backend_resp << "    if(beresp.ttl <= #{@min_ttl}s){"
    @output_array_for_backend_resp << "      set beresp.ttl = #{@min_ttl}s;"
    @output_array_for_backend_resp << "    }else if(beresp.ttl >= #{@max_ttl}s){"
    @output_array_for_backend_resp << "      set beresp.ttl = #{@max_ttl}s;"
    @output_array_for_backend_resp << "    }"
    @output_array_for_backend_resp << "    return (deliver);"
    ## HTTPヘッダのcache-controlにmax-ageが設定されていない場合，min_ttlとdefault_ttlの大きい方をセットする
    @output_array_for_backend_resp << "  }else{"
    @output_array_for_backend_resp << "    set beresp.ttl = #{(@min_ttl >= @default_ttl)? @min_ttl : @default_ttl}s;"
    @output_array_for_backend_resp << "    return (deliver);"
    @output_array_for_backend_resp << "  }"
  end

  def store_code_for_hash
    # FORWARD COOKIES
    @output_array_for_hash << "  hash_data(req.http.Cookie);"
    # FORWARD HEADERS
    if @forward_headers.items[0] != "*"
      @forward_headers.items.each_with_index do |header, index|
        @output_array_for_hash << "  hash_data(req.http.#{header});"
      end
      # @output_array_for_hash << "  return(lookup);"
    end

    @output_array_for_hash << "  hash_data(req.http.X-PARAMS);" if @trusted_signers.enabled
  end

  def store_code_for_miss
    ## 署名付きURLの利用している場合，署名および有効期限の検証
    if @trusted_signers.enabled
      @output_array_for_miss << "  call check_valid;"
      # サブルーチンのコール後，真偽値の結果がreq.http.is_allowedに格納される
      @output_array_for_miss << "  if(req.http.is_allowed != \"true\"){"
      @output_array_for_miss << "    return (synth(403, \"Forbidden\"));"
      @output_array_for_miss << "  }"
      @output_array_for_miss << "  unset req.http.is_allowed;"
      @output_array_for_miss << "  unset req.http.X-PARAMS;"
    end
    @output_array_for_miss << "  return (fetch);"
  end

  def delete_symbol(str)
    result_str = ""
    for i in 1..str.size
      if str[i-1] == "." || str[i-1] == "-"
      else
        result_str = result_str + str[i-1]
      end
    end
    return result_str
  end
end

class DefaultBehavior < Behavior
end

class AdditionBehavior < Behavior
  # defaultのbehavior以外はoriginに対してPATHが付加する
  def initialize(cache_behavior)
    super(cache_behavior)
    @url = cache_behavior.path_pattern
  end

  def store_code_for_recv
    # behaviorの条件
    ## PATH PATTERN
    ## origindomain/PATH もしくは origindomain/PATH?param=hoge であるurlの条件
    @output_array_for_recv << "if(req.url ~ \"^(#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}|#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}\\?.*)\"){"
    super
    @output_array_for_recv << "}"
    @output_array_for_recv.each_with_index do |code_line, index|
      code_line.insert(0, "  ")
    end
  end

  def store_code_for_backend_resp
    # behaviorの条件
    ## PATHの条件分岐を追加
    ## origindomain/PATH もしくは origindomain/PATH?param=hoge であるurlの条件
    @output_array_for_backend_resp << "if(bereq.url ~ \"^(#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}|#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}\\?.*)\"){"
    super
    @output_array_for_backend_resp << "}"
    @output_array_for_backend_resp.each_with_index do |code_line, index|
      code_line.insert(0, "  ")
    end
  end

  def store_code_for_hash
    # behaviorの条件
    ## PATHの条件分岐を追加
    ## origindomain/PATH もしくは origindomain/PATH?param=hoge であるurlの条件
    if @forward_headers.items[0] != "*"
      @output_array_for_hash << "if(req.url ~ \"^(#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}|#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}\\?.*)\"){"
      super
      @output_array_for_hash << "}"
      @output_array_for_hash.each do |code_line|
        code_line.insert(0, "  ")
      end
    end
  end

  def store_code_for_miss
    # behaviorの条件
    ## PATHの条件分岐を追加
    ## origindomain/PATH もしくは origindomain/PATH?param=hoge であるurlの条件
    if @forward_headers.items[0] != "*"
      @output_array_for_miss << "if(req.url ~ \"^(#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}|#{@url.gsub(/\./, "\\.").gsub(/\*/, ".*")}\\?.*)\"){"
      super
      @output_array_for_miss << "}"
      @output_array_for_miss.each do |code_line|
        code_line.insert(0, "  ")
      end
    end
  end

end
