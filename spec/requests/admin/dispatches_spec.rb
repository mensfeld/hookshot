# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Dispatches" do
  let(:auth_headers) do
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "changeme")
    { "HTTP_AUTHORIZATION" => credentials }
  end

  describe "GET /admin/dispatches" do
    it "requires authentication" do
      get "/admin/dispatches"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists deliveries when authenticated" do
      webhook = create(:webhook)
      target = create(:target)
      create(:delivery, webhook: webhook, target: target)

      get "/admin/dispatches", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "filters by status" do
      webhook = create(:webhook)
      target = create(:target)
      create(:delivery, webhook: webhook, target: target, status: :success)
      create(:delivery, webhook: webhook, target: target, status: :failed)

      get "/admin/dispatches", params: { status: "failed" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
    end

    it "filters by target" do
      webhook = create(:webhook)
      target1 = create(:target)
      target2 = create(:target)
      create(:delivery, webhook: webhook, target: target1)
      create(:delivery, webhook: webhook, target: target2)

      get "/admin/dispatches", params: { target_id: target1.id }, headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/dispatches/:id" do
    let(:delivery) { create(:delivery) }

    it "shows delivery details" do
      get "/admin/dispatches/#{delivery.id}", headers: auth_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/dispatches/:id/retry" do
    let(:webhook) { create(:webhook) }
    let(:target) { create(:target) }

    context "with retryable delivery" do
      let(:delivery) { create(:delivery, webhook: webhook, target: target, status: :failed, attempts: 1) }

      it "resets status to pending" do
        post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers

        expect(delivery.reload.status).to eq("pending")
      end

      it "enqueues a dispatch job" do
        expect {
          post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers
        }.to have_enqueued_job(DispatchJob)
      end

      it "redirects to dispatch show" do
        post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers

        expect(response).to redirect_to(admin_dispatch_path(delivery))
      end
    end

    context "with non-retryable delivery" do
      let(:delivery) { create(:delivery, webhook: webhook, target: target, status: :success) }

      it "shows alert and does not retry" do
        post "/admin/dispatches/#{delivery.id}/retry", headers: auth_headers

        expect(response).to redirect_to(admin_dispatch_path(delivery))
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "bulk retry controls on GET /admin/dispatches" do
    let(:target) { create(:target, name: "Reconciler") }
    let(:other_target) { create(:target, name: "Other") }
    let!(:retryable) { create(:delivery, :retryable, target: target) }
    let!(:other_retryable) { create(:delivery, :retryable, target: other_target) }
    let!(:exhausted) { create(:delivery, status: :failed, attempts: Delivery::MAX_TOTAL_ATTEMPTS, target: target) }
    let!(:succeeded) { create(:delivery, :success, target: target) }

    def page_html
      Nokogiri::HTML(response.body)
    end

    it "renders a selection checkbox only for retryable deliveries" do
      get "/admin/dispatches", headers: auth_headers

      values = page_html.css("input[name='delivery_ids[]']").map { |input| input["value"] }
      expect(values).to contain_exactly(retryable.id.to_s, other_retryable.id.to_s)
      expect(page_html.css("input[name='delivery_ids[]']").map { |input| input["form"] }.uniq).to eq([ "bulk-retry-form" ])
    end

    it "renders a select-all checkbox and a disabled retry selected button" do
      get "/admin/dispatches", headers: auth_headers

      expect(page_html.at_css("input[data-bulk-select-target='all']")).to be_present
      expect(page_html.at_css("#bulk-retry-form button[type='submit']")["disabled"]).not_to be_nil
    end

    it "offers retrying all retryable deliveries matching the filters" do
      get "/admin/dispatches", params: { status: "failed", target_id: target.id }, headers: auth_headers

      button = page_html.at_css("form[action='/admin/dispatches/retry_all'] button")
      expect(button.text).to eq("Retry all matching (1)")
      form = button.ancestors("form").first
      expect(form.at_css("input[name='status']")["value"]).to eq("failed")
      expect(form.at_css("input[name='target_id']")["value"]).to eq(target.id.to_s)
    end

    it "carries the filters and page into the retry selected form" do
      get "/admin/dispatches", params: { status: "failed", target_id: target.id, page: 1 }, headers: auth_headers

      form = page_html.at_css("#bulk-retry-form")
      expect(form["action"]).to eq("/admin/dispatches/retry_selected")
      expect(form.css("input[type='hidden']").to_h { |input| [ input["name"], input["value"] ] })
        .to include("status" => "failed", "target_id" => target.id.to_s, "page" => "1")
    end

    it "hides the bulk controls when nothing can be retried" do
      get "/admin/dispatches", params: { status: "success" }, headers: auth_headers

      expect(page_html.at_css("#bulk-retry-form")).to be_nil
      expect(page_html.at_css("form[action='/admin/dispatches/retry_all']")).to be_nil
      expect(page_html.at_css("input[data-bulk-select-target='all']")).to be_nil
    end

    it "offers retry all even when the current page has no retryable rows" do
      create_list(:delivery, 50, :success, target: target, created_at: 1.minute.from_now)

      get "/admin/dispatches", headers: auth_headers

      expect(page_html.at_css("#bulk-retry-form")).to be_nil
      expect(page_html.at_css("form[action='/admin/dispatches/retry_all'] button").text).to eq("Retry all matching (2)")
    end
  end

  describe "POST /admin/dispatches/retry_selected" do
    let(:target) { create(:target) }
    let!(:first) { create(:delivery, :retryable, target: target) }
    let!(:second) { create(:delivery, :retryable, target: target) }
    let!(:untouched) { create(:delivery, :retryable, target: target) }
    let!(:succeeded) { create(:delivery, :success, target: target) }

    def retry_selected(ids, **extra)
      post "/admin/dispatches/retry_selected", params: { delivery_ids: ids, **extra }, headers: auth_headers
    end

    it "requires authentication" do
      post "/admin/dispatches/retry_selected", params: { delivery_ids: [ first.id ] }

      expect(response).to have_http_status(:unauthorized)
      expect(first.reload).to be_failed
    end

    it "queues the selected retryable deliveries and leaves others alone" do
      expect { retry_selected([ first.id, second.id ]) }.to have_enqueued_job(DispatchJob).exactly(2).times

      expect([ first, second ].map { |delivery| delivery.reload.status }).to eq(%w[pending pending])
      expect(untouched.reload).to be_failed
      expect(flash[:notice]).to eq("Queued 2 dispatches for retry.")
    end

    it "skips selected deliveries that are no longer retryable" do
      retry_selected([ first.id, succeeded.id, 0 ])

      expect(first.reload).to be_pending
      expect(succeeded.reload).to be_success
      expect(flash[:notice]).to eq("Queued 1 dispatch for retry. Skipped 2 that are no longer retryable.")
    end

    it "ignores duplicate and blank ids" do
      expect { retry_selected([ first.id, first.id.to_s, "" ]) }.to have_enqueued_job(DispatchJob).exactly(:once)

      expect(flash[:notice]).to eq("Queued 1 dispatch for retry.")
    end

    it "returns to the same filters and page" do
      retry_selected([ first.id ], status: "failed", target_id: target.id, page: 2)

      expect(response).to redirect_to(admin_dispatches_path(status: "failed", target_id: target.id, page: 2))
    end

    it "alerts when nothing was selected" do
      expect { post "/admin/dispatches/retry_selected", params: { status: "failed" }, headers: auth_headers }
        .not_to have_enqueued_job(DispatchJob)

      expect(response).to redirect_to(admin_dispatches_path(status: "failed"))
      expect(flash[:alert]).to eq("Select at least one dispatch to retry")
    end

    it "alerts when none of the selected deliveries can be retried" do
      retry_selected([ succeeded.id ])

      expect(flash[:alert]).to eq("No dispatches could be retried")
    end

    it "caps a single request at the bulk limit" do
      stub_const("Admin::DispatchesController::BULK_RETRY_LIMIT", 2)

      expect { retry_selected([ first.id, second.id, untouched.id ]) }.to have_enqueued_job(DispatchJob).exactly(2).times
      expect(untouched.reload).to be_failed
    end
  end

  describe "POST /admin/dispatches/retry_all" do
    let(:target) { create(:target) }
    let(:other_target) { create(:target) }
    let!(:failed_deliveries) { create_list(:delivery, 3, :retryable, target: target) }
    let!(:other_failed) { create(:delivery, :retryable, target: other_target) }
    let!(:exhausted) { create(:delivery, status: :failed, attempts: Delivery::MAX_TOTAL_ATTEMPTS, target: target) }
    let!(:succeeded) { create(:delivery, :success, target: target) }

    it "requires authentication" do
      post "/admin/dispatches/retry_all"

      expect(response).to have_http_status(:unauthorized)
    end

    it "retries every retryable delivery matching the target filter, across pages" do
      expect {
        post "/admin/dispatches/retry_all", params: { status: "failed", target_id: target.id }, headers: auth_headers
      }.to have_enqueued_job(DispatchJob).exactly(3).times

      expect(failed_deliveries.map { |delivery| delivery.reload.status }.uniq).to eq([ "pending" ])
      expect(other_failed.reload).to be_failed
      expect(exhausted.reload).to be_failed
      expect(flash[:notice]).to eq("Queued 3 dispatches for retry.")
      expect(response).to redirect_to(admin_dispatches_path(status: "failed", target_id: target.id))
    end

    it "retries across all targets without a target filter" do
      expect { post "/admin/dispatches/retry_all", headers: auth_headers }.to have_enqueued_job(DispatchJob).exactly(4).times
    end

    it "does nothing when the status filter excludes failed deliveries" do
      expect { post "/admin/dispatches/retry_all", params: { status: "success" }, headers: auth_headers }
        .not_to have_enqueued_job(DispatchJob)

      expect(flash[:alert]).to eq("No dispatches could be retried")
    end

    it "reports what is left when the bulk limit is reached" do
      stub_const("Admin::DispatchesController::BULK_RETRY_LIMIT", 2)

      post "/admin/dispatches/retry_all", params: { target_id: target.id }, headers: auth_headers

      expect(flash[:notice]).to eq("Queued 2 dispatches for retry. 1 more remain, use Retry all again.")
      expect(failed_deliveries.count { |delivery| delivery.reload.pending? }).to eq(2)
    end
  end
end
