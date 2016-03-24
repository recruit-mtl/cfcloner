require "../../pkey.rb"

class Signer
  def initialize(kpis)
    @kpis = kpis
  end

  def store_code
    code_for_pkey = ""
    @kpis.each do |kpi|
      code_for_pkey += <<-EOS
    if(req.http.Var_KPI ~ "#{kpi}"){
      set req.http.Var_PKey = {"#{$pkey[kpi.to_sym]}"};
    }
      EOS
    end

    <<-EOS
import std;
import signature;

sub check_valid {
  if(req.http.X-PARAMS != ""){
    set req.http.Var_Expires = regsub(req.http.X-PARAMS,  ".*[?&]Expires=(\\w+).*", "\\1");
    set req.http.Var_Signature = regsub(req.http.X-PARAMS,  ".*[?&]Signature=([\\w-_~]+).*", "\\1");
    set req.http.Var_KPI = regsub(req.http.X-PARAMS,  ".*[?&]Key-Pair-Id=(\\w+).*", "\\1");

    set req.http.Var_Signature = regsuball(req.http.Var_Signature,  "-", "+");
    set req.http.Var_Signature = regsuball(req.http.Var_Signature,  "_", "=");
    set req.http.Var_Signature = regsuball(req.http.Var_Signature,  "~", "/");

    set req.http.Var_Url = regsub(req.url,  "\\?.*", "");
    set req.http.Var_Plain = {"{"Statement":[{"Resource":""} + "http://" + req.http.host + req.http.Var_Url + {"","Condition":{"DateLessThan":{"AWS:EpochTime":"} + req.http.Var_Expires + "}}}]}";

#{code_for_pkey}
    if(req.http.Var_PKey && signature.valid_signature(req.http.Var_Plain, req.http.Var_Signature, req.http.Var_PKey)){
      // If request is not expired, set the result to TRUE.
      set req.http.is_allowed = std.integer(req.http.Var_Expires, 0) >= std.time2integer(now);
    }else{
      // If public key is empty or verification of signature is failed
      set req.http.is_allowed = false;
    }

    unset req.http.Var_PKey;
    unset req.http.Var_Url;
    unset req.http.Var_Plain;
    unset req.http.Var_Expires;
    unset req.http.Var_Signature;
    unset req.http.Var_KPI;
  }
}
    EOS
  end
end
