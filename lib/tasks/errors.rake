namespace :errors do
  desc "Delete resolved errors older than 30 days"
  task cleanup: :environment do
    count = ErrorRecord.resolved
      .where("resolved_at < ?", 30.days.ago)
      .delete_all
    puts "Deleted #{count} old resolved errors"
  end
end
