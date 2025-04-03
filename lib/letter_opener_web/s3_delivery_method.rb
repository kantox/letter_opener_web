# frozen_string_literal: true

require 'letter_opener/delivery_method'

module LetterOpenerWeb
  # Delivery method to store files in and AWS S3 bucket
  class S3DeliveryMethod < DeliveryMethod
    cattr_accessor :s3_client
    delegate :s3_client, to: 'self.class'
    delegate :bucket, to: 'LetterOpenerWeb.config.s3_bucket'

    def initialize(*)
      raise('`aws-sdk-s3` gem is required for this delivery method') unless defined?(Aws::S3::Client)

      super
      self.class.s3_client ||= Aws::S3::Client.new(region: Aws.config[:region] || ENV.fetch('AWS_REGION', nil))
    end

    def deliver!(mail)
      super.tap do |_outcome|
        location = mail['location_plain'] || mail['location_rich']
        raise ArgumentError unless location

        deliver_to_s3!(File.dirname(location.to_s))
      end
    end

    def deliver_to_s3!(folder)
      Pathname.new(folder).glob('*').each do |path|
        key = path.to_s.sub(LetterOpenerWeb.config.letters_location.to_s << '/', '')
        s3_client.put_object(
          bucket: bucket,
          key: key,
          body: path.open('rb'),
          acl: 'bucket-owner-full-control'
        )
      end
    end
  end
end
