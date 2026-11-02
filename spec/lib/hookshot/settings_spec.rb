# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hookshot::Settings do
  {
    "RETENTION_DAYS" => [ :retention_days, 30 ],
    "MAX_PAYLOAD_SIZE" => [ :max_payload_size, 1_048_576 ],
    "JOB_CONCURRENCY" => [ :job_concurrency, 1 ]
  }.each do |name, (reader, default)|
    describe ".#{reader}" do
      around do |example|
        original = ENV.fetch(name, nil)
        example.run
      ensure
        ENV[name] = original
      end

      it "returns #{default} when #{name} is unset" do
        ENV.delete(name)

        expect(described_class.public_send(reader)).to eq(default)
      end

      it "returns the value when #{name} is a positive integer" do
        ENV[name] = "7"

        expect(described_class.public_send(reader)).to eq(7)
      end

      it "accepts underscores in #{name}" do
        ENV[name] = "1_000"

        expect(described_class.public_send(reader)).to eq(1000)
      end

      [ "", "0", "-5", "+7", " 7 ", "7\n", "1__0", "_1", "abc", "10MB", "1.5", "0x10" ].each do |value|
        it "rejects #{name}=#{value.inspect}" do
          ENV[name] = value

          expect { described_class.public_send(reader) }
            .to raise_error(described_class::InvalidError, "#{name} must be a positive integer, got #{value.inspect}")
          expect { described_class.validate! }.to raise_error(described_class::InvalidError, /\A#{name} /)
        end
      end
    end
  end

  describe ".validate!" do
    it "passes when every setting is unset or valid" do
      expect { described_class.validate! }.not_to raise_error
    end
  end

  describe "config/initializers/settings.rb" do
    let(:initializer) { Rails.root.join("config/initializers/settings.rb") }

    around do |example|
      originals = described_class::DEFAULTS.keys.index_with { |name| ENV.fetch(name, nil) }
      example.run
    ensure
      originals.each { |name, value| ENV[name] = value }
    end

    it "boots with valid settings" do
      ENV["RETENTION_DAYS"] = "7"
      ENV["MAX_PAYLOAD_SIZE"] = "1_000_000"
      ENV["JOB_CONCURRENCY"] = "2"

      expect { load initializer }.not_to raise_error
    end

    described_class::DEFAULTS.each_key do |name|
      it "refuses to boot with an invalid #{name}" do
        ENV[name] = "0"

        expect { load initializer }
          .to raise_error(described_class::InvalidError, "#{name} must be a positive integer, got \"0\"")
      end
    end
  end

  describe "config/queue.yml" do
    around do |example|
      original = ENV.fetch("JOB_CONCURRENCY", nil)
      example.run
    ensure
      ENV["JOB_CONCURRENCY"] = original
    end

    let(:default_workers) do
      config = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
      config.dig("production", "workers").find { |worker| worker["queues"] == "default" }
    end

    it "runs JOB_CONCURRENCY processes for the default queue" do
      ENV["JOB_CONCURRENCY"] = "3"

      expect(default_workers["processes"]).to eq(3)
    end

    it "raises the settings error for an invalid JOB_CONCURRENCY" do
      ENV["JOB_CONCURRENCY"] = "abc"

      expect { default_workers }.to raise_error(described_class::InvalidError, /JOB_CONCURRENCY/)
    end
  end
end
