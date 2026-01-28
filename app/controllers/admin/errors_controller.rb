module Admin
  # Manages error records in the error tracking system.
  # Provides viewing, filtering, resolution, and deletion of application errors.
  class ErrorsController < AdminController
    before_action :set_error_record, only: %i[show resolve unresolve destroy]

    # Lists error records with tab filtering (unresolved/resolved/all).
    # @return [void]
    def index
      @tab = params[:tab].presence&.to_sym || :unresolved
      @error_records = filter_by_tab(@tab).recent_first.page(params[:page]).per(50)
    end

    # Shows detailed view of a single error record.
    # @return [void]
    def show
      # @error_record set by before_action
    end

    # Marks an error record as resolved.
    # @return [void]
    def resolve
      if @error_record.resolve!
        redirect_to error_path(@error_record), notice: "Error marked as resolved."
      else
        redirect_to error_path(@error_record), alert: "Failed to resolve error."
      end
    end

    # Marks an error record as unresolved.
    # @return [void]
    def unresolve
      if @error_record.unresolve!
        redirect_to error_path(@error_record), notice: "Error marked as unresolved."
      else
        redirect_to error_path(@error_record), alert: "Failed to unresolve error."
      end
    end

    # Deletes a single error record.
    # @return [void]
    def destroy
      @error_record.destroy
      redirect_to errors_path, notice: "Error record deleted."
    end

    # Bulk deletes all resolved error records.
    # @return [void]
    def destroy_all
      count = ErrorRecord.resolved.delete_all
      redirect_to errors_path, notice: "Deleted #{count} resolved error(s)."
    end

    private

    # Sets the @error_record instance variable from params[:id].
    # @return [void]
    def set_error_record
      @error_record = ErrorRecord.find(params[:id])
    end

    # Filters error records by tab selection.
    # @param tab [Symbol] the tab to filter by (:unresolved, :resolved, or :all)
    # @return [ActiveRecord::Relation] the filtered error records
    def filter_by_tab(tab)
      case tab
      when :resolved then ErrorRecord.resolved
      when :all then ErrorRecord.all
      else ErrorRecord.unresolved
      end
    end
  end
end
