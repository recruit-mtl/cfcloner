# -*- coding: utf-8 -*-
require "cfcloner/version"
require "aws-sdk"
require File.dirname(__FILE__) + "/Backend"
require File.dirname(__FILE__) + "/Behavior"

module Cfcloner
  # CloudFrontのインスタンスを生成
  cf = Aws::CloudFront::Client.new(
    region: 'ap-northeast-1'
  )
  # ディストリビューションのidを指定してディストリビューションの情報を取ってくる
  resp = cf.get_distribution_config({
    id: '**************'
  })

  # vclに書き出すコードの配列を宣言
  entire_code = Array.new
  # vclのバージョンを指定
  entire_code << "vcl 4.0;"

  # Backend情報を格納する配列を宣言
  backend_array = Array.new
  resp.distribution_config.origins.items.each_with_index do |origin, index|
    # CFのOriginの数だけbackend配列に格納
    backend_array[index] = Backend.new(origin)
    # Backendのvcl用コードを生成
    backend_array[index].store_code_for_declar_backend
    # entire_codeに格納
    entire_code.concat(backend_array[index].output_array)
  end

  # Bahavior情報を格納する配列を宣言
  behavior_array = Array.new
  # CFのbehaviorのDefault Behavior以外をbehavior配列に格納
  resp.distribution_config.cache_behaviors.items.each_with_index do |behavior, index|
    behavior_array[index] = AdditionBehavior.new(behavior)
  end
  # CFのbehaviorのDefault Behaviorをbehavior配列に格納
  behavior_array[behavior_array.length] = DefaultBehavior.new(resp.distribution_config.default_cache_behavior)

  # Behaviorのvcl用コードを生成
  behavior_array.each_with_index do |behavior, index|
    behavior_array[index].store_code_for_recv
    behavior_array[index].store_code_for_hash
    behavior_array[index].store_code_for_backend_resp
  end

  # vcl_recv箇所をentire_codeに格納
  entire_code << "sub vcl_recv {"
  behavior_array.each_with_index do |behavior, index|
    entire_code.concat(behavior.output_array_for_recv)
  end
  entire_code << "}"

  # vcl_hash箇所をentire_codeに格納
  entire_code << "sub vcl_hash {"
  behavior_array.each_with_index do |behavior, index|
    entire_code.concat(behavior.output_array_for_hash)
  end
  entire_code << "}"

  # vcl_backend_response箇所をentire_codeに格納
  entire_code << "sub vcl_backend_response {"
  behavior_array.each_with_index do |behavior, index|
    entire_code.concat(behavior.output_array_for_backend_resp)
  end
  entire_code << "}"


  # vcl_hit箇所をentire_codeに格納
  entire_code << "sub vcl_hit {"
  # vcl_deliverでは参照できないobj.ttlの値を一時的に保存する
  entire_code << "  set req.http.Remain-ttl-tmp = obj.ttl;"
  entire_code << "}"

  # vcl_deliverをentire_codeに格納
  entire_code << "sub vcl_deliver {"
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
  File.open('/etc/varnish/default.vcl', 'w') do |file|
    for entire_code_line in entire_code do
      file.puts entire_code_line
    end
  end
end
