class Backend
  attr_reader :output_array
  def initialize(origin)
    @name = delete_symbol(origin.id)
    @host = origin.domain_name
    @port = origin.custom_origin_config.http_port
    @output_array = Array.new
  end

  # ELBを参照する際に，hostが一意に定まらない問題
  def store_code_for_declar_backend
    @output_array.push("backend #{@name} {")
    @output_array.push("  .host = \"#{@host}\";")
    @output_array.push("  .port = \"#{@port}\";")
    @output_array.push("}")
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
