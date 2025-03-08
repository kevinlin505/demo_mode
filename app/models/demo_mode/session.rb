# frozen_string_literal: true

module DemoMode
  class Session < ActiveRecord::Base
    attribute :variant, default: :default

    if ActiveRecord.gem_version >= Gem::Version.new('7.2')
      enum :status, { processing: 'processing', successful: 'successful', failed: 'failed' }, default: 'processing'
    else
      attribute :status, default: :processing
      enum status: { processing: 'processing', successful: 'successful', failed: 'failed' }
    end

    validates :persona_name, :variant, presence: true
    validates :persona, presence: { message: :required }, on: :create, if: :persona_name?
    validate :successful_status_requires_signinable

    belongs_to :signinable, polymorphic: true, optional: true

    before_create :set_password!

    delegate :begin_demo,
      :custom_sign_in?,
      :display_credentials?,
      to: :persona,
      allow_nil: true

    def signinable_username
      signinable.public_send(DemoMode.signinable_username_method)
    end

    def signinable_metadata
      metadata = {}
      DemoMode.metadata.map do |data|
        keys = nested_keys(data)

        if keys.length > 1
          metadata[keys.last] = keys.inject(signinable) do |obj, method_name|
            if obj.try(method_name).present?
              obj.public_send(method_name)
            end
          end
        elsif signinable.try(data).present?
          metadata[data] = signinable.public_send(data)
        end
      end

      metadata
    end

    # Heads up: finding a persona is not guaranteed (e.g. past sessions)
    def persona
      DemoMode.personas.find { |p| p.name.to_s == persona_name.to_s }
    end

    def save_and_generate_account!(**options)
      transaction do
        save!
        AccountGenerationJob.perform_now(self, **options)
      end
    end

    def save_and_generate_account_later!(**options)
      transaction do
        save!
        AccountGenerationJob.perform_later(self, **options)
      end
    end

    private

    def nested_keys(metadata)
      metadata.to_s.split('#')
    end

    def set_password!
      self.signinable_password ||= DemoMode.current_password
    end

    def successful_status_requires_signinable
      if status == 'successful' && signinable.blank?
        errors.add(:status, 'cannot be successful if signinable is not present')
      end
    end
  end
end
