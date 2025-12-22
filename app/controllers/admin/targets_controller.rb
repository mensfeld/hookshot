# frozen_string_literal: true

module Admin
  # Manages target CRUD operations and testing.
  class TargetsController < AdminController
    before_action :set_target, only: %i[show edit update destroy test]

    # Lists all targets with their filters.
    # @return [void]
    def index
      @targets = Target.includes(:filters).order(:name)
    end

    # Shows target details.
    # @return [void]
    def show
    end

    # Renders the new target form.
    # @return [void]
    def new
      @target = Target.new
      @target.filters.build
    end

    # Renders the edit target form.
    # @return [void]
    def edit
      @target.filters.build if @target.filters.empty?
    end

    # Creates a new target.
    # @return [void]
    def create
      @target = Target.new(target_params)

      if @target.save
        redirect_to admin_targets_path, notice: "Target created successfully"
      else
        render :new, status: :unprocessable_entity
      end
    end

    # Updates an existing target.
    # @return [void]
    def update
      if @target.update(target_params)
        redirect_to admin_targets_path, notice: "Target updated successfully"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Deletes a target.
    # @return [void]
    def destroy
      @target.destroy
      redirect_to admin_targets_path, notice: "Target deleted successfully"
    end

    # Sends a test webhook to the target.
    # @return [void]
    def test
      test_payload = {
        event: "hookshot.test",
        timestamp: Time.current.iso8601,
        message: "This is a test webhook from Hookshot"
      }.to_json

      client = HttpClient.new(url: @target.url, timeout: @target.timeout)
      headers = @target.custom_headers.merge(
        "Content-Type" => "application/json",
        "X-Hookshot-Test" => "true"
      )

      result = client.post(body: test_payload, headers: headers)

      if result.success?
        redirect_to admin_targets_path, notice: "Test successful! Response: #{result.status_code}"
      else
        redirect_to admin_targets_path, alert: "Test failed: #{result.error || "HTTP #{result.status_code}"}"
      end
    end

    private

    # Sets the target from the ID parameter.
    # @return [void]
    def set_target
      @target = Target.find(params[:id])
    end

    # Permits and transforms target parameters.
    # @return [ActionController::Parameters] permitted parameters
    def target_params
      permitted = params.require(:target).permit(
        :name, :url, :active, :timeout,
        custom_headers_keys: [],
        custom_headers_values: [],
        filters_attributes: %i[id filter_type field operator value _destroy]
      )

      # Convert custom_headers arrays to hash
      if permitted[:custom_headers_keys].present?
        keys = permitted.delete(:custom_headers_keys)
        values = permitted.delete(:custom_headers_values) || []
        permitted[:custom_headers] = keys.zip(values).reject { |k, _| k.blank? }.to_h
      else
        permitted.delete(:custom_headers_keys)
        permitted.delete(:custom_headers_values)
      end

      permitted
    end
  end
end
