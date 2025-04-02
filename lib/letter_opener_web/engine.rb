# frozen_string_literal: true

require 'letter_opener'
require 'letter_opener_web/delivery_method'
require 'letter_opener_web/s3_delivery_method'

module LetterOpenerWeb
  class Engine < ::Rails::Engine
    isolate_namespace LetterOpenerWeb

    initializer 'letter_opener_web.add_delivery_method' do
      ActiveSupport.on_load :action_mailer do
        ActionMailer::Base.add_delivery_method(
          :letter_opener_web,
          LetterOpenerWeb::DeliveryMethod,
          location: LetterOpenerWeb.config.letters_location
        )
        ActionMailer::Base.add_delivery_method(
          :letter_opener_web_s3,
          LetterOpenerWeb::S3DeliveryMethod,
          location: LetterOpenerWeb.config.letters_location,
          s3_bucket: ENV['LETTER_OPENER_WEB_S3_BUCKET']
        )
      end
    end
  end
end
