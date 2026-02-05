# frozen_string_literal: true

module Admin
  # Manages webhook viewing and replay operations.
  class WebhooksController < AdminController
    before_action :set_webhook, only: %i[show destroy replay]

    # Lists all webhooks with pagination and filtering.
    # @return [void]
    def index
      @webhooks = Webhook.includes(:deliveries).order(received_at: :desc)
      @webhooks = filter_by_date(@webhooks)
      @webhooks = filter_by_search(@webhooks)
      @webhooks = @webhooks.page(params[:page]).per(50)
    end

    # Shows webhook details and its deliveries.
    # @return [void]
    def show
      @deliveries = @webhook.deliveries.includes(:target).order(created_at: :desc)
    end

    # Deletes a webhook and its deliveries.
    # @return [void]
    def destroy
      @webhook.destroy
      redirect_to admin_webhooks_path, notice: "Webhook deleted successfully"
    end

    # Replays the webhook to all active targets.
    # @return [void]
    def replay
      WebhookDispatcher.new(@webhook).dispatch_to_all_targets
      redirect_to admin_webhook_path(@webhook), notice: "Webhook queued for replay to all active targets"
    end

    private

    # Sets the webhook from the ID parameter.
    # @return [void]
    def set_webhook
      @webhook = Webhook.find(params[:id])
    end

    # Applies date filters to the webhook scope.
    # @param scope [ActiveRecord::Relation] the base query scope
    # @return [ActiveRecord::Relation] filtered scope
    def filter_by_date(scope)
      scope = scope.where("received_at >= ?", params[:date_from]) if params[:date_from].present?
      scope = scope.where("received_at <= ?", params[:date_to].to_date.end_of_day) if params[:date_to].present?
      scope
    end

    # Applies text search filter to the webhook scope.
    # @param scope [ActiveRecord::Relation] the base query scope
    # @return [ActiveRecord::Relation] filtered scope
    def filter_by_search(scope)
      return scope if params[:q].blank?

      scope.search_text(params[:q])
    end
  end
end
