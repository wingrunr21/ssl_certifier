require 'spec_helper'

describe OpenURI do
  context "normal http operations" do
    before(:each) do
      @proxies = %w[http_proxy HTTP_PROXY ftp_proxy FTP_PROXY no_proxy]
      @old_proxies = @proxies.map {|k| ENV[k] }
      @proxies.each {|k| ENV[k] = nil }
    end

    after(:each) do
      @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
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

    it 'should return 404 for a bad url' do
      with_http do |srv, dr, url|
        lambda { open("#{url}/not-exist") {} }.should raise_error(OpenURI::HTTPError)
        #TODO: somehow get the status from the lambda
        #exc.io.status[0].should == "404"
      end
    end

    it 'should read the string "foo_ou"' do
      with_http do |srv, dr, url|
        open("#{dr}/foo_ou", "w") {|f| f << "foo_ou" }
        u = URI("#{url}/foo_ou")
        open(u) do |f|
          f.status[0].should == "200"
          f.read.should == "foo_ou"
        end
      end
    end

    it 'should raise an ArgumentError when open is given too many args' do
      lambda { open("http://192.0.2.1/tma", "r", 0666, :extra) {} }.should raise_error(ArgumentError)
    end

    it 'should raise an ArgumentError when open is given an invalid argument' do
      lambda { open("http://127.0.0.1/", :invalid_option=>true) {} }.should raise_error(ArgumentError)
    end

    it 'should raise a Timeout::Error when a read times out' do
      TCPServer.open("127.0.0.1", 0) do |serv|
        port = serv.addr[1]
        th = Thread.new {
          sock = serv.accept
          begin
            req = sock.gets("\r\n\r\n")
            req.should match %r{\AGET /foo/bar }
            sock.print "HTTP/1.0 200 OK\r\n"
            sock.print "Content-Length: 4\r\n\r\n"
            sleep 1
            sock.print "ab\r\n"
          ensure
            sock.close
          end
        }
        begin
          lambda { URI("http://127.0.0.1:#{port}/foo/bar").read(:read_timeout=>0.01) }.should raise_error(Timeout::Error)
        ensure
          Thread.kill(th)
          th.join
        end
      end
    end

    it 'should read when opening in various modes' do
      with_http do |srv, dr, url|
        open("#{dr}/mode", "w") {|f| f << "mode" }
        open("#{url}/mode", "r") do |f|
          f.status[0].should == "200"
          f.read.should == "mode"
        end
        open("#{url}/mode", "r", 0600) do |f|
          f.status[0].should == "200"
          f.read.should == "mode"
        end
        lambda { open("#{url}/mode", "a") {} }.should raise_error(ArgumentError)
        open("#{url}/mode", "r:us-ascii") do |f|
          f.read.encoding.should == Encoding::US_ASCII
        end
        open("#{url}/mode", "r:utf-8") do |f|
          f.read.encoding.should == Encoding::UTF_8
        end
        lambda { open("#{url}/mode", "r:invalid-encoding") {} }.should raise_error(ArgumentError)
      end
    end

    it 'should open a url when a block is not specified' do
      with_http do |srv, dr, url|
        open("#{dr}/without_block", "w") {|g| g << "without_block" }
        begin
          f = open("#{url}/without_block")
          f.status[0].should == "200"
          f.read.should == "without_block"
        ensure
          f.close
        end
      end
    end

    it 'should read the same headers for header1 and header2' do
      myheader1 = 'barrrr'
      myheader2 = nil
      with_http do |srv, dr, url|
        srv.mount_proc("/h/") {|req, res| myheader2 = req['myheader']; res.body = "foo" }
        open("#{url}/h/", 'MyHeader'=>myheader1) do |f|
          f.read.should == "foo"
          myheader1.should == myheader2
        end
      end
    end

    it 'should not open with multiple proxy options' do
      lambda { open("http://127.0.0.1/", :proxy_http_basic_authentication=>true, :proxy=>true) {} }.should raise_error(ArgumentError)
    end

    it 'should not open with a non-http proxy' do
      lambda { open("http://127.0.0.1/", :proxy=>URI("ftp://127.0.0.1/")) {} }.should raise_error(RuntimeError)
    end

    it 'should open a url via a proxy' do
      with_http do |srv, dr, url|
        log = ''
        proxy = WEBrick::HTTPProxyServer.new({
          :ServerType => Thread,
          :Logger => WEBrick::Log.new(NullLog),
          :AccessLog => [[NullLog, ""]],
          :ProxyAuthProc => lambda {|req, res|
            log << req.request_line
          },
          :BindAddress => '127.0.0.1',
          :Port => 0})
        _, proxy_port, _, proxy_host = proxy.listeners[0].addr
        proxy_url = "http://#{proxy_host}:#{proxy_port}/"
        begin
          th = proxy.start
          open("#{dr}/proxy", "w") {|f| f << "proxy" }
          open("#{url}/proxy", :proxy=>proxy_url) do |f|
            f.status[0].should == "200"
            f.read.should == "proxy"
          end
          log.should match /#{Regexp.quote url}/
          log.clear

          open("#{url}/proxy", :proxy=>URI(proxy_url)) do |f|
            f.status[0].should == "200"
            f.read.should == "proxy"
          end
          log.should match /#{Regexp.quote url}/
          log.clear

          open("#{url}/proxy", :proxy=>nil) do |f|
            f.status[0].should == "200"
            f.read.should == "proxy"
          end
          log.should == ""
          log.clear

          lambda { open("#{url}/proxy", :proxy=>:invalid) {} }.should raise_error(ArgumentError)
          log.should == ""
          log.clear

          with_env("http_proxy"=>proxy_url) {
            # should not use proxy for 127.0.0.0/8.
            open("#{url}/proxy") do |f|
              f.status[0].should == "200"
              f.read.should == "proxy"
            end
          }
          log.should == ""
          log.clear
        ensure
          proxy.shutdown
        end
      end
    end

    it 'should open a url via proxy with http basic authentication' do
      with_http do |srv, dr, url|
        log = ''
        proxy = WEBrick::HTTPProxyServer.new({
          :ServerType => Thread,
          :Logger => WEBrick::Log.new(NullLog),
          :AccessLog => [[NullLog, ""]],
          :ProxyAuthProc => lambda {|req, res|
            log << req.request_line
            if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
              raise WEBrick::HTTPStatus::ProxyAuthenticationRequired
            end
          },
          :BindAddress => '127.0.0.1',
          :Port => 0})
        _, proxy_port, _, proxy_host = proxy.listeners[0].addr
        proxy_url = "http://#{proxy_host}:#{proxy_port}/"
        begin
          th = proxy.start
          open("#{dr}/proxy", "w") {|f| f << "proxy" }
          lambda { open("#{url}/proxy", :proxy=>proxy_url) {} }.should raise_error(OpenURI::HTTPError)
          #TODO: somehow extract the status from the lambda
          #exc.io.status[0].should == "407"
          log.should match /#{Regexp.quote url}/
          log.clear

          open("#{url}/proxy", :proxy_http_basic_authentication=>[proxy_url, "user", "pass"]) do |f|
            f.status[0].should == "200"
            f.read.should == "proxy"
          end
          log.should match /#{Regexp.quote url}/
          log.clear

          lambda { open("#{url}/proxy", :proxy_http_basic_authentication=>[true, "user", "pass"]) {} }.should raise_error(ArgumentError)
          log.should == ""
          log.clear
        ensure
          proxy.shutdown
        end
      end
    end

    it 'should open urls with redirects' do
      with_http do |srv, dr, url|
        srv.mount_proc("/r1/") {|req, res| res.status = 301; res["location"] = "#{url}/r2"; res.body = "r1" }
        srv.mount_proc("/r2/") {|req, res| res.body = "r2" }
        srv.mount_proc("/to-file/") {|req, res| res.status = 301; res["location"] = "file:///foo" }
        open("#{url}/r1/") do |f|
          f.base_uri.to_s.should == "#{url}/r2"
          f.read.should == "r2"
        end
        lambda { open("#{url}/r1/", :redirect=>false) {} }.should raise_error(OpenURI::HTTPRedirect)
        lambda { open("#{url}/to-file/") {} }.should raise_error(RuntimeError)
      end
    end

    it 'should raise a RuntimeError if it enters a redirect loop' do
      with_http do |srv, dr, url|
        srv.mount_proc("/r1/") {|req, res| res.status = 301; res["location"] = "#{url}/r2"; res.body = "r1" }
        srv.mount_proc("/r2/") {|req, res| res.status = 301; res["location"] = "#{url}/r1"; res.body = "r2" }
        lambda { open("#{url}/r1/") {} }.should raise_error(RuntimeError)
      end
    end

    it 'should open a URI through a relative redirect' do
      TCPServer.open("127.0.0.1", 0) do |serv|
        port = serv.addr[1]
        th = Thread.new {
          sock = serv.accept
          begin
            req = sock.gets("\r\n\r\n")
            req.should match %r{\AGET /foo/bar }
            sock.print "HTTP/1.0 302 Found\r\n"
            sock.print "Location: ../baz\r\n\r\n"
          ensure
            sock.close
          end
          sock = serv.accept
          begin
            req = sock.gets("\r\n\r\n")
            req.should match %r{\AGET /baz }
            sock.print "HTTP/1.0 200 OK\r\n"
            sock.print "Content-Length: 4\r\n\r\n"
            sock.print "ab\r\n"
          ensure
            sock.close
          end
        }
        begin
          content = URI("http://127.0.0.1:#{port}/foo/bar").read
          content.should == "ab\r\n"
        ensure
          Thread.kill(th)
          th.join
        end
      end
    end

    it 'should raise a OpenURI::HTTPError if an invalid redirect is encountered' do
      TCPServer.open("127.0.0.1", 0) do |serv|
        port = serv.addr[1]
        th = Thread.new {
          sock = serv.accept
          begin
            req = sock.gets("\r\n\r\n")
            req.should match %r{\AGET /foo/bar }
            sock.print "HTTP/1.0 302 Found\r\n"
            sock.print "Location: ::\r\n\r\n"
          ensure
            sock.close
          end
        }
        begin
          lambda { URI("http://127.0.0.1:#{port}/foo/bar").read }.should raise_error(OpenURI::HTTPError)
        ensure
          Thread.kill(th)
          th.join
        end
      end
    end

    it 'should open a url with basic authentication after being redirected' do
      with_http do |srv, dr, url|
        srv.mount_proc("/r1/") {|req, res| res.status = 301; res["location"] = "#{url}/r2" }
        srv.mount_proc("/r2/") do |req, res|
          if req["Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise WEBrick::HTTPStatus::Unauthorized
          end
          res.body = "r2"
        end
        lambda{ open("#{url}/r2/") {} }.should raise_error(OpenURI::HTTPError)
        #TODO: somehow get the status from the lambda
        #exc.io.status[0].should == "401"
        open("#{url}/r2/", :http_basic_authentication=>['user', 'pass']) do |f|
          f.read.should == "r2"
        end
        lambda { open("#{url}/r1/", :http_basic_authentication=>['user', 'pass']) {} }.should raise_error(OpenURI::HTTPError)
        #TODO: somehow get the status from the lambda
        #exc.io.status[0].should == "401"
      end
    end

    it 'should raise an ArgumentError if user information is incorrectly specified in the url' do
      if "1.9.0" <= RUBY_VERSION
        lambda { open("http://user:pass@127.0.0.1/") {} }.should raise_error(ArgumentError)
      end
    end

    it 'should open a url and report the progress' do
      with_http do |srv, dr, url|
        content = "a" * 100000
        srv.mount_proc("/data/") {|req, res| res.body = content }
        length = []
        progress = []
        open("#{url}/data/",
             :content_length_proc => lambda {|n| length << n },
             :progress_proc => lambda {|n| progress << n }
            ) {|f|
          length.length.should == 1
          length[0].should == content.length
          progress.length.should be > 1
          progress.should == progress.sort
          progress[-1].should == content.length
          f.read.should == content
        }
      end
    end

    it 'should open a url and report the progress when the response is chunked' do
      with_http do |srv, dr, url|
        content = "a" * 100000
        srv.mount_proc("/data/") {|req, res| res.body = content; res.chunked = true }
        length = []
        progress = []
        open("#{url}/data/",
             :content_length_proc => lambda {|n| length << n },
             :progress_proc => lambda {|n| progress << n }
            ) {|f|
          length.length.should == 1
          length[0].should be nil
          progress.length.should be > 1
          progress.should == progress.sort
          progress[-1].should == content.length
          f.read.should == content
        }
      end
    end

    it 'should open a url and read from it' do
      with_http do |srv, dr, url|
        open("#{dr}/uriread", "w") {|f| f << "uriread" }
        data = URI("#{url}/uriread").read
        data.status[0].should == "200"
        data.should == "uriread"
      end
    end

    it 'should work with different encodings' do
      with_http do |srv, dr, url|
        content_u8 = "\u3042"
        content_ej = "\xa2\xa4".force_encoding("euc-jp")
        srv.mount_proc("/u8/") {|req, res| res.body = content_u8; res['content-type'] = 'text/plain; charset=utf-8' }
        srv.mount_proc("/ej/") {|req, res| res.body = content_ej; res['content-type'] = 'TEXT/PLAIN; charset=EUC-JP' }
        srv.mount_proc("/nc/") {|req, res| res.body = "aa"; res['content-type'] = 'Text/Plain' }
        open("#{url}/u8/") do |f|
          f.read.should == content_u8
          f.content_type.should == "text/plain"
          f.charset.should == "utf-8"
        end
        open("#{url}/ej/") do |f|
          f.read.should == content_ej
          f.content_type.should == "text/plain"
          f.charset.should == "euc-jp"
        end
        open("#{url}/nc/") do |f|
          f.read.should == "aa"
          f.content_type.should == "text/plain"
          f.charset.should == "iso-8859-1"
          f.charset { "unknown" }.should == "unknown"
        end
      end
    end

    it 'should open a url with quoted attribute values' do
      with_http do |srv, dr, url|
        content_u8 = "\u3042"
        srv.mount_proc("/qu8/") {|req, res| res.body = content_u8; res['content-type'] = 'text/plain; charset="utf\-8"' }
        open("#{url}/qu8/") do |f|
          f.read.should == content_u8
          f.content_type.should == "text/plain"
          f.charset.should == "utf-8"
        end
      end
    end

    it 'should read the last modified date from a url' do
      with_http do |srv, dr, url|
        srv.mount_proc("/data/") {|req, res| res.body = "foo"; res['last-modified'] = 'Fri, 07 Aug 2009 06:05:04 GMT' }
        open("#{url}/data/") do |f|
          f.read.should == "foo"
          f.last_modified.should == Time.utc(2009,8,7,6,5,4)
        end
      end
    end

    it 'should read data with various content encoding' do
      with_http do |srv, dr, url|
        content = "abc" * 10000
        Zlib::GzipWriter.wrap(StringIO.new(content_gz="".force_encoding("ascii-8bit"))) {|z| z.write content }
        srv.mount_proc("/data/") {|req, res| res.body = content_gz; res['content-encoding'] = 'gzip' }
        srv.mount_proc("/data2/") {|req, res| res.body = content_gz; res['content-encoding'] = 'gzip'; res.chunked = true }
        srv.mount_proc("/noce/") {|req, res| res.body = content_gz }
        open("#{url}/data/") do |f|
          f.content_encoding.should == ['gzip']
          f.read.force_encoding("ascii-8bit").should == content_gz
        end
        open("#{url}/data2/") do |f|
          f.content_encoding.should == ['gzip']
          f.read.force_encoding("ascii-8bit").should == content_gz
        end
        open("#{url}/noce/") do |f|
          f.content_encoding.should == []
          f.read.force_encoding("ascii-8bit").should == content_gz
        end
      end
    end

    # 192.0.2.0/24 is TEST-NET.  [RFC3330]

    it 'should find the proxy for a given url' do
      URI("http://192.0.2.1/").find_proxy.should be nil
      URI("ftp://192.0.2.1/").find_proxy.should be nil
      with_env('http_proxy'=>'http://127.0.0.1:8080') {
        URI("http://192.0.2.1/").find_proxy.should == URI('http://127.0.0.1:8080')
        URI("ftp://192.0.2.1/").find_proxy.should be nil
      }
      with_env('ftp_proxy'=>'http://127.0.0.1:8080') {
        URI("http://192.0.2.1/").find_proxy.should be nil
        URI("ftp://192.0.2.1/").find_proxy.should == URI('http://127.0.0.1:8080')
      }
      with_env('REQUEST_METHOD'=>'GET') {
        URI("http://192.0.2.1/").find_proxy.should be nil
      }
      with_env('CGI_HTTP_PROXY'=>'http://127.0.0.1:8080', 'REQUEST_METHOD'=>'GET') {
        URI("http://192.0.2.1/").find_proxy.should == URI('http://127.0.0.1:8080')
      }
      with_env('http_proxy'=>'http://127.0.0.1:8080', 'no_proxy'=>'192.0.2.2') {
        URI("http://192.0.2.1/").find_proxy.should == URI('http://127.0.0.1:8080')
        URI("http://192.0.2.2/").find_proxy.should be nil
      }
    end

    it 'should find a proxy for a given url with a case sensitive env' do
      with_env('http_proxy'=>'http://127.0.0.1:8080', 'REQUEST_METHOD'=>'GET') {
        URI("http://192.0.2.1/").find_proxy.should == URI('http://127.0.0.1:8080')
      }
      with_env('HTTP_PROXY'=>'http://127.0.0.1:8081', 'REQUEST_METHOD'=>'GET') {
        URI("http://192.0.2.1/").find_proxy.should be nil
      }
      with_env('http_proxy'=>'http://127.0.0.1:8080', 'HTTP_PROXY'=>'http://127.0.0.1:8081', 'REQUEST_METHOD'=>'GET') {
        URI("http://192.0.2.1/").find_proxy.should == URI('http://127.0.0.1:8080')
      }
    end unless RUBY_PLATFORM =~ /mswin|mingw/

    it 'should raise exceptions on invalid ftp requests' do
      lambda { URI("ftp://127.0.0.1/").read }.should raise_error(ArgumentError)
      lambda { URI("ftp://127.0.0.1/a%0Db").read }.should raise_error(ArgumentError)
      lambda { URI("ftp://127.0.0.1/a%0Ab").read }.should raise_error(ArgumentError)
      lambda { URI("ftp://127.0.0.1/a%0Db/f").read }.should raise_error(ArgumentError)
      lambda { URI("ftp://127.0.0.1/a%0Ab/f").read }.should raise_error(ArgumentError)
      lambda { URI("ftp://127.0.0.1/d/f;type=x") }.should raise_error(URI::InvalidComponentError)
    end

    it 'should perform FTP operations' do
      TCPServer.open("127.0.0.1", 0) {|serv|
        _, port, _, host = serv.addr
        th = Thread.new {
          s = serv.accept
          begin
            s.print "220 Test FTP Server\r\n"
            s.gets.should == "USER anonymous\r\n"; s.print "331 name ok\r\n"
            s.gets.should match /\APASS .*\r\n\z/; s.print "230 logged in\r\n"
            s.gets.should == "TYPE I\r\n"; s.print "200 type set to I\r\n"
            s.gets.should == "CWD foo\r\n"; s.print "250 CWD successful\r\n"
            s.gets.should == "PASV\r\n"
            TCPServer.open("127.0.0.1", 0) {|data_serv|
              _, data_serv_port, _, data_serv_host = data_serv.addr
              hi = data_serv_port >> 8
              lo = data_serv_port & 0xff
              s.print "227 Entering Passive Mode (127,0,0,1,#{hi},#{lo}).\r\n"
              s.gets.should == "RETR bar\r\n"; s.print "150 file okay\r\n"
              data_sock = data_serv.accept
              begin
                data_sock << "content"
              ensure
                data_sock.close
              end
              s.print "226 transfer complete\r\n"
              s.gets.should be nil
            }
          ensure
            s.close if s
          end
        }
        begin
          content = URI("ftp://#{host}:#{port}/foo/bar").read
          content.should == "content"
        ensure
          Thread.kill(th)
          th.join
        end
      }
    end

    it 'should perform active FTP operations' do
      TCPServer.open("127.0.0.1", 0) do |serv|
        _, port, _, host = serv.addr
        th = Thread.new {
          s = serv.accept
          begin
            content = "content"
            s.print "220 Test FTP Server\r\n"
            s.gets.should == "USER anonymous\r\n"; s.print "331 name ok\r\n"
            s.gets.should match /\APASS .*\r\n\z/; s.print "230 logged in\r\n"
            s.gets.should == "TYPE I\r\n"; s.print "200 type set to I\r\n"
            s.gets.should == "CWD foo\r\n"; s.print "250 CWD successful\r\n"
            m = s.gets.should match /\APORT 127,0,0,1,(\d+),(\d+)\r\n\z/
            active_port = m[1].to_i << 8 | m[2].to_i
            TCPSocket.open("127.0.0.1", active_port) do |data_sock|
              s.print "200 data connection opened\r\n"
              s.gets.should == "RETR bar\r\n"; s.print "150 file okay\r\n"
              begin
                data_sock << content
              ensure
                data_sock.close
              end
              s.print "226 transfer complete\r\n"
              s.gets.should be nil
            end
          ensure
            s.close if s
          end
        }
        begin
          content = URI("ftp://#{host}:#{port}/foo/bar").read(:ftp_active_mode=>true)
          content.should == "content"
        ensure
          Thread.kill(th)
          th.join
        end
      end
    end

    it 'should perform FTP operations in ascii' do
      TCPServer.open("127.0.0.1", 0) do |serv|
        _, port, _, host = serv.addr
        th = Thread.new {
          s = serv.accept
          begin
            content = "content"
            s.print "220 Test FTP Server\r\n"
            s.gets.should == "USER anonymous\r\n"; s.print "331 name ok\r\n"
            s.gets.should match /\APASS .*\r\n\z/; s.print "230 logged in\r\n"
            s.gets.should == "TYPE I\r\n"; s.print "200 type set to I\r\n"
            s.gets.should == "CWD /foo\r\n"; s.print "250 CWD successful\r\n"
            s.gets.should == "TYPE A\r\n"; s.print "200 type set to A\r\n"
            s.gets.should == "SIZE bar\r\n"; s.print "213 #{content.bytesize}\r\n"
            s.gets.should == "PASV\r\n"
            TCPServer.open("127.0.0.1", 0) {|data_serv|
              _, data_serv_port, _, data_serv_host = data_serv.addr
              hi = data_serv_port >> 8
              lo = data_serv_port & 0xff
              s.print "227 Entering Passive Mode (127,0,0,1,#{hi},#{lo}).\r\n"
              s.gets.should == "RETR bar\r\n"; s.print "150 file okay\r\n"
              data_sock = data_serv.accept
              begin
                data_sock << content
              ensure
                data_sock.close
              end
              s.print "226 transfer complete\r\n"
              s.gets.should be nil
            }
          ensure
            s.close if s
          end
        }
        begin
          length = []
          progress = []
          content = URI("ftp://#{host}:#{port}/%2Ffoo/b%61r;type=a").read(
           :content_length_proc => lambda {|n| length << n },
           :progress_proc => lambda {|n| progress << n })
          content.should == "content"
          length.should == [7]
          progress.inject(&:+).should == 7
        ensure
          Thread.kill(th)
          th.join
        end
      end
    end

    it 'should allow ftp via an http proxy' do
      TCPServer.open("127.0.0.1", 0) do |proxy_serv|
        proxy_port = proxy_serv.addr[1]
        th = Thread.new {
          proxy_sock = proxy_serv.accept
          begin
            req = proxy_sock.gets("\r\n\r\n")
            req.should match %r{\AGET ftp://192.0.2.1/foo/bar }
            proxy_sock.print "HTTP/1.0 200 OK\r\n"
            proxy_sock.print "Content-Length: 4\r\n\r\n"
            proxy_sock.print "ab\r\n"
          ensure
            proxy_sock.close
          end
        }
        begin
          with_env('ftp_proxy'=>"http://127.0.0.1:#{proxy_port}") {
            content = URI("ftp://192.0.2.1/foo/bar").read
            content.should == "ab\r\n"
          }
        ensure
          Thread.kill(th)
          th.join
        end
      end
    end

    it 'should allow ftp via an http proxy with basic authorization' do
      TCPServer.open("127.0.0.1", 0) do |proxy_serv|
        proxy_port = proxy_serv.addr[1]
        th = Thread.new {
          proxy_sock = proxy_serv.accept
          begin
            req = proxy_sock.gets("\r\n\r\n")
            req.should match %r{\AGET ftp://192.0.2.1/foo/bar }
            req.should match %r{Proxy-Authorization: Basic #{['proxy-user:proxy-password'].pack('m').chomp}\r\n}
            proxy_sock.print "HTTP/1.0 200 OK\r\n"
            proxy_sock.print "Content-Length: 4\r\n\r\n"
            proxy_sock.print "ab\r\n"
          ensure
            proxy_sock.close
          end
        }
        begin
          content = URI("ftp://192.0.2.1/foo/bar").read(
            :proxy_http_basic_authentication => ["http://127.0.0.1:#{proxy_port}", "proxy-user", "proxy-password"])
          content.should == "ab\r\n"
        ensure
          Thread.kill(th)
          th.join
        end
      end
    end
  end
end
