# ssl_certifier [![Build Status](https://secure.travis-ci.org/wingrunr21/ssl_certifier.png)](http://travis-ci.org/wingrunr21/ssl_certifier)

This gem provides the [cURL ca certficates](http://curl.haxx.se/ca/cacert.pem) to allow Ruby/OpenURI to verify the authenticity of SSL certificates.  Ruby 1.9.x will, by default, attempt to verify SSL certificates when it performs secure operations.  This is good from a security standpoint, but when Ruby cannot find the root certificates (like on most Windows installations), SSL errors will occur.  This gem solves that problem.

## Installation
```gem install ssl_certifier```


### Rails 3
Put this in your Gemfile:
```gem 'ssl_certifier'```
## Usage
In Rails 3, the gem will be automatically loaded with your environment via Bundler.

In Ruby scripts, simply require the Gem along with your other dependencies:

```require 'ssl_certifier'```

## Issues
Report via Github


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/wingrunr21/ssl_certifier/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

