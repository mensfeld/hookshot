# frozen_string_literal: true

require "rails_helper"

RSpec.describe EndpointsHelper do
  describe "#endpoint_receive_url" do
    it "uses the plain receive URL for the default endpoint" do
      expect(helper.endpoint_receive_url(Endpoint.default)).to eq("http://test.host/webhooks/receive")
    end

    it "appends the slug for other endpoints" do
      expect(helper.endpoint_receive_url(build(:endpoint, slug: "deploys"))).to eq("http://test.host/webhooks/receive/deploys")
    end
  end
end
