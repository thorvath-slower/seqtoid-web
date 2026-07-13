class DropNextgenDeletionLogs < ActiveRecord::Migration[7.0]
  # CZID-295: the nextgen_deletion_logs table is orphaned after the NextGen
  # removal (CZID-283 deleted the NextGenDeletionLog model and the
  # hard_delete_nextgen_objects job). Nothing reads or writes it. Drop it.
  #
  # Reversible: the block form recreates the exact column set from the
  # consolidated migration / schema.rb so `db:rollback` restores the table.
  def change
    safety_assured do
      drop_table "nextgen_deletion_logs", charset: "utf8", collation: "utf8_unicode_ci" do |t|
        t.bigint "user_id", null: false, comment: "The user id of the user who deleted the object"
        t.string "user_email", comment: "The email of the user who deleted the object"
        t.bigint "rails_object_id", comment: "The id of the object that was deleted (Rails ID)"
        t.string "object_id", null: false, comment: "The id of the object that was deleted (NextGen UUID)"
        t.string "object_type", null: false, comment: "The type of object deleted, e.g. Sample, Workflow"
        t.datetime "soft_deleted_at", precision: nil, comment: "When the object was marked as soft deleted"
        t.datetime "hard_deleted_at", precision: nil, comment: "When the object was successfully hard deleted"
        t.string "metadata_json", comment: "Generic JSON-string format for recording additional information about the object"
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
      end
    end
  end
end
