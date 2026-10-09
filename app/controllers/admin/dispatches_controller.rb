# frozen_string_literal: true

module Admin
  # Manages delivery viewing and retry operations.
  class DispatchesController < AdminController
    # Maximum number of deliveries a single bulk retry request queues.
    BULK_RETRY_LIMIT = 1000

    before_action :set_delivery, only: %i[show retry]

    # Lists all deliveries with pagination and filtering.
    # @return [void]
    def index
      @deliveries = Delivery.includes(:webhook, :target).order(created_at: :desc)
      @deliveries = filter_deliveries(@deliveries)
      @deliveries = @deliveries.page(params[:page]).per(50)

      @targets = Target.order(:name)
      @retryable_count = filter_deliveries(Delivery.retryable).count
    end

    # Shows delivery details.
    # @return [void]
    def show
    end

    # Retries a failed delivery.
    # @return [void]
    def retry
      if @delivery.retry!
        redirect_to admin_dispatch_path(@delivery), notice: "Delivery queued for retry"
      else
        redirect_to admin_dispatch_path(@delivery), alert: "This delivery cannot be retried"
      end
    end

    # Retries the deliveries selected on the index page.
    # @return [void]
    def retry_selected
      ids = Array(params[:delivery_ids]).compact_blank.uniq

      if ids.empty?
        redirect_to admin_dispatches_path(listing_params), alert: "Select at least one dispatch to retry"
        return
      end

      ids = ids.first(BULK_RETRY_LIMIT)
      queued = retry_deliveries(Delivery.where(id: ids).order(:id))
      redirect_with_retry_result(queued: queued, skipped: ids.size - queued)
    end

    # Retries every retryable delivery matching the current status and target filters, across all pages.
    # @return [void]
    def retry_all
      scope = filter_deliveries(Delivery.retryable)
      total = scope.count
      queued = retry_deliveries(scope.order(:id).limit(BULK_RETRY_LIMIT))

      redirect_with_retry_result(queued: queued, remaining: total - queued)
    end

    private

    # Sets the delivery from the ID parameter.
    # @return [void]
    def set_delivery
      @delivery = Delivery.find(params[:id])
    end

    # Listing filters and page to return to after a bulk action.
    # @return [Hash] permitted status, target_id and page parameters
    def listing_params
      { status: params[:status], target_id: params[:target_id], page: params[:page] }.compact_blank
    end

    # Queues a retry for each retryable delivery in the scope.
    # @param scope [ActiveRecord::Relation] deliveries to retry
    # @return [Integer] number of deliveries queued
    def retry_deliveries(scope)
      scope.to_a.count(&:retry!)
    end

    # Redirects back to the listing with a summary of a bulk retry.
    # @param queued [Integer] number of deliveries queued for retry
    # @param skipped [Integer] number of selected deliveries that could not be retried
    # @param remaining [Integer] number of matching deliveries left over because of the bulk limit
    # @return [void]
    def redirect_with_retry_result(queued:, skipped: 0, remaining: 0)
      if queued.zero?
        redirect_to admin_dispatches_path(listing_params), alert: "No dispatches could be retried"
        return
      end

      message = "Queued #{helpers.pluralize(queued, 'dispatch')} for retry."
      message += " Skipped #{skipped} that #{skipped == 1 ? 'is' : 'are'} no longer retryable." if skipped.positive?
      message += " #{remaining} more remain, use Retry all again." if remaining.positive?
      redirect_to admin_dispatches_path(listing_params), notice: message
    end

    # Applies status and target filters to the deliveries scope.
    # @param scope [ActiveRecord::Relation] the base query scope
    # @return [ActiveRecord::Relation] filtered scope
    def filter_deliveries(scope)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(target_id: params[:target_id]) if params[:target_id].present?
      scope
    end
  end
end
