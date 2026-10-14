# frozen_string_literal: true

require "rails_helper"

RSpec.describe EndpointTarget do
  subject { described_class.new(endpoint: create(:endpoint), target: create(:target, :without_endpoints)) }

  it { is_expected.to belong_to(:endpoint) }
  it { is_expected.to belong_to(:target) }
  it { is_expected.to validate_uniqueness_of(:target_id).scoped_to(:endpoint_id) }
end
