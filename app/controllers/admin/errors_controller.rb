module Admin
  class ErrorsController < AdminController
    before_action :set_error_record, only: %i[show resolve unresolve destroy]

    def index
      @tab = params[:tab].presence&.to_sym || :unresolved
      @error_records = filter_by_tab(@tab).recent_first.page(params[:page]).per(50)
    end

    def show
      # @error_record set by before_action
    end

    def resolve
      if @error_record.resolve!
        redirect_to error_path(@error_record), notice: 'Error marked as resolved.'
      else
        redirect_to error_path(@error_record), alert: 'Failed to resolve error.'
      end
    end

    def unresolve
      if @error_record.unresolve!
        redirect_to error_path(@error_record), notice: 'Error marked as unresolved.'
      else
        redirect_to error_path(@error_record), alert: 'Failed to unresolve error.'
      end
    end

    def destroy
      @error_record.destroy
      redirect_to errors_path, notice: 'Error record deleted.'
    end

    def destroy_all
      count = Admin::ErrorRecord.resolved.delete_all
      redirect_to errors_path, notice: "Deleted #{count} resolved error(s)."
    end

    private

    def set_error_record
      @error_record = Admin::ErrorRecord.find(params[:id])
    end

    def filter_by_tab(tab)
      case tab
      when :resolved then Admin::ErrorRecord.resolved
      when :all then Admin::ErrorRecord.all
      else Admin::ErrorRecord.unresolved
      end
    end
  end
end
