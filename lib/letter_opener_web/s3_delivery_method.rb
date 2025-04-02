# frozen_string_literal: true

require 'letter_opener/delivery_method'

module LetterOpenerWeb
  class S3DeliveryMethod < DeliveryMethod
    attr_writer :s3_client

    def initialize(*)
      raise('`aws-sdk-s3` gem is required for this delivery method') unless defined?(Aws::S3::Client)

      super
    end

    def deliver!(mail)
      super.tap do |_outcome|
        location = mail['location_plain'] || mail['location_rich']
        break(outcome) unless location

        folder = File.dirname(location.to_s)
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

    def s3_client
      @s3_client ||= Aws::S3::Client.new(region: Aws.config[:region] || ENV['AWS_REGION'])
    end

    def bucket
      LetterOpenerWeb.config.s3_bucket
    end
  end
end
