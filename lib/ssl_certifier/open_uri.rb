module OpenURI
  CaCertOptions = {:ssl_ca_cert => File.join(File.expand_path("../../certs/", __FILE__), 'cacert.pem')}
  def OpenURI.open_http(buf, target, proxy, options)
    options = CaCertOptions.merge(options)
    super(buf, target, proxy, options)
  end
end