require 'spec_helper'

describe OpenURI do
  
  after(:each) do
    @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
  end
  
  context "normal http operations" do
    before(:each) do
      @proxies = %w[http_proxy HTTP_PROXY ftp_proxy FTP_PROXY no_proxy]
      @old_proxies = @proxies.map {|k| ENV[k] }
      @proxies.each {|k| ENV[k] = nil }
    end
    
    it 'should return 200' do
      with_http do |srv, dr, url|
        open("#{dr}/foo200", "w") {|f| f << "foo200" }
        open("#{url}/foo200") do |f|
          f.status[0].should == "200"
          f.read.should == "foo200"
        end
      end
    end
    
    it 'should return 200 for a big file' do
      with_http do |srv, dr, url|
        content = "foo200big"*10240
        open("#{dr}/foo200big", "w") {|f| f << content }
        open("#{url}/foo200big") do |f|
          f.status[0].should == "200"
          f.read.should == content
        end
      end
    end
  end
  
  context "SSL operations" do
    before(:each) do
      @proxies = %w[http_proxy HTTP_PROXY https_proxy HTTPS_PROXY ftp_proxy FTP_PROXY no_proxy]
      @old_proxies = @proxies.map {|k| ENV[k] }
      @proxies.each {|k| ENV[k] = nil }
    end
    
    it 'should validate with ca_cert specified' do
      with_https do |srv, dr, url|
        cacert_filename = "#{dr}/cacert.pem"
        open(cacert_filename, "w") {|f| f << CA_CERT }
        open("#{dr}/data", "w") {|f| f << "ddd" }
        open("#{url}/data", :ssl_ca_cert => cacert_filename) do |f|
          f.status[0].should == "200"
          f.read.should == "ddd"
        end
        open("#{url}/data", :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE) do |f|
          f.status[0].should == "200"
          f.read.should == "ddd"
        end
        
        lambda { open("#{url}/data") {} }.should raise_error(OpenSSL::SSL::SSLError)
      end
    end
    
    it 'should work via proxy' do
      with_https do |srv, dr, url|
        cacert_filename = "#{dr}/cacert.pem"
        open(cacert_filename, "w") {|f| f << CA_CERT }
        cacert_directory = "#{dr}/certs"
        Dir.mkdir cacert_directory
        hashed_name = "%08x.0" % OpenSSL::X509::Certificate.new(CA_CERT).subject.hash
        open("#{cacert_directory}/#{hashed_name}", "w") {|f| f << CA_CERT }
        
        prxy = WEBrick::HTTPProxyServer.new({
          :ServerType => Thread,
          :Logger => WEBrick::Log.new(NullLog),
          :AccessLog => [[sio=StringIO.new, WEBrick::AccessLog::COMMON_LOG_FORMAT]],
          :BindAddress => '127.0.0.1',
          :Port => 0})
        _, p_port, _, p_host = prxy.listeners[0].addr
        
        begin
          th = prxy.start
          open("#{dr}/proxy", "w") {|f| f << "proxy" }
          
          open("#{url}/proxy", :proxy=>"http://#{p_host}:#{p_port}/", :ssl_ca_cert => cacert_filename) do |f|
            f.status[0].should == "200"
            f.read.should == "proxy"
          end
          sio.string.should match %r[CONNECT #{url.sub(%r{\Ahttps://}, '')} ]
          sio.truncate(0); sio.rewind
          
          open("#{url}/proxy", :proxy=>"http://#{p_host}:#{p_port}/", :ssl_ca_cert => cacert_directory) do |f|
            f.status[0].should == "200"
            f.read.should == "proxy"
          end
          sio.string.should match %r[CONNECT #{url.sub(%r{\Ahttps://}, '')} ]
          sio.truncate(0); sio.rewind
        ensure
          prxy.shutdown
        end
      end
    end
    
    #TODO: make this a better URL
    it 'should validate without ca_cert specified' do
      with_https do |srv, dr, url|
        open("https://github.com/wingrunr21/ssl_certifier/raw/master/spec/data.txt") do |f|
          f.status[0].should == "200"
          f.read.should == "ddd"
        end
        open("https://github.com/wingrunr21/ssl_certifier/raw/master/spec/data.txt", :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE) do |f|
          f.status[0].should == "200"
          f.read.should == "ddd"
        end
        
        #lambda { open("#{url}/data") {} }.should_not raise_error(OpenSSL::SSL::SSLError)
      end
    end
  end
end