require 'open-uri'
require 'openssl'
require 'webrick'
require 'webrick/https'
require 'webrick/httpproxy'
require 'stringio'
require 'zlib'
require 'ssl_certifier'

dr = File.dirname(File.expand_path(__FILE__))

#Read in various files needed for SSL
SERVER_CERT = File.read(File.join(dr, 'certs', 'server_cert.pem'))
SERVER_KEY = File.read(File.join(dr, 'certs', 'server_key'))
CA_CERT = File.read(File.join(dr, 'certs', 'ca_cert.pem'))

#NullLog
NullLog = Object.new
def NullLog.<<(arg)
end

#Various with methods from the open-uri unit tests
def with_http
  Dir.mktmpdir {|dr|
    srv = WEBrick::HTTPServer.new({
      :DocumentRoot => dr,
      :ServerType => Thread,
      :Logger => WEBrick::Log.new(NullLog),
      :AccessLog => [[NullLog, ""]],
      :BindAddress => '127.0.0.1',
      :Port => 0})
    _, port, _, host = srv.listeners[0].addr
    begin
      th = srv.start
      yield srv, dr, "http://#{host}:#{port}"
    ensure
      srv.shutdown
    end
  }
end

def with_env(h)
  begin
    old = {}
    h.each_key {|k| old[k] = ENV[k] }
    h.each {|k, v| ENV[k] = v }
    yield
  ensure
    h.each_key {|k| ENV[k] = old[k] }
  end
end

def with_https
  Dir.mktmpdir {|dr|
    srv = WEBrick::HTTPServer.new({
      :DocumentRoot => dr,
      :ServerType => Thread,
      :Logger => WEBrick::Log.new(NullLog),
      :AccessLog => [[NullLog, ""]],
      :SSLEnable => true,
      :SSLCertificate => OpenSSL::X509::Certificate.new(SERVER_CERT),
      :SSLPrivateKey => OpenSSL::PKey::RSA.new(SERVER_KEY),
      :BindAddress => '127.0.0.1',
      :Port => 0})
    _, port, _, host = srv.listeners[0].addr
    begin
      th = srv.start
      yield srv, dr, "https://#{host}:#{port}"
    ensure
      srv.shutdown
    end
  }
end