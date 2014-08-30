require 'redis'
require 'zlib'
require 'digest/md5'

class Redreloader
  class << self
    attr_accessor :redis
    attr_accessor :ttl
    
    def [](key)
      val = with_binary_redis { @redis.getrange(key, 16, -1) }
      Zlib::Inflate.inflate(val) if val && val != ""
    end
    
    def []=(key, val)
      with_binary_redis { @redis.set(key, calcmd5(val) + Zlib::Deflate.deflate(val), ex: @ttl) }
    end

    def calcmd5(val)
      Digest::MD5.digest val
    end

    def digest(key)
      data = with_binary_redis { @redis.getrange(key, 0, 15) }
      data if data != ""
    end

    def if_changed_from(key, old_digest)
      if (new_digest = digest(key)) && new_digest != old_digest
        newdata = self[key]
        yield(newdata, new_digest) if newdata
      end
    end
    
    def with_binary_redis
      original_encoding = Encoding.default_external
      Encoding.default_external = Encoding.find('binary')
      yield
    ensure
      Encoding.default_external = original_encoding
    end
  end
end
