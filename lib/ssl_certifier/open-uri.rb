module OpenURI
  CaCertOptions = {:ssl_ca_cert => File.join(File.expand_path("../../../certs/", __FILE__), 'cacert.pem')}
  
  class << self
    alias_method :open_http_without_ca_cert, :open_http
    
    def OpenURI.open_http(buf, target, proxy, options) # :nodoc:
      options = CaCertOptions.merge(options)
      OpenURI.open_http_without_ca_cert(buf, target, proxy, options)
    end
  end
end