require 'redis'
require 'zlib'
require 'digest/md5'

class Redreloader
  def initialize(redis_config)
    @redis = Redis.new(redis_config)
    @redis_sub = Redis.new(redis_config)
  end

  def [](key)
    val = with_binary_redis { @redis.getrange(key, 16, -1) }
    Zlib::Inflate.inflate(val) if val && val != ""
  end

  def []=(key, val)
  with_binary_redis { @redis.set(key, self.class.calcmd5(val) + Zlib::Deflate.deflate(val)) }
end

  def self.calcmd5(val)
    Digest::MD5.digest val
  end

  def digest(key)
    data = with_binary_redis { @redis.getrange(key, 0, 15) }
    data if data != ""
  end

  def process_changes(key, old_digest, &bl)
    @redis_sub.subscribe("__keyspace@0__:#{key}") do |on|
      on.message do |channel, message|
        old_digest = yield_if_changed(key, old_digest, &bl)
      end

      on.subscribe do |channel, message|
        # run it here to avoid race condition of change between check and subscribe
        old_digest = yield_if_changed(key, old_digest, &bl)
      end
    end
  end

  def yield_if_changed(key, old_digest, &bl)
    if (new_digest = digest(key)) && new_digest != old_digest
      newdata = self[key]
      bl.call(newdata, new_digest) if newdata
    end
    new_digest
  end

  def with_binary_redis
    original_encoding = Encoding.default_external
    Encoding.default_external = Encoding.find('binary')
    yield
  ensure
    Encoding.default_external = original_encoding
  end
end
