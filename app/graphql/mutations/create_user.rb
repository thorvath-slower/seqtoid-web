class Mutations::CreateUser < Mutations::BaseMutation
  include GraphqlAuthHelpers

  field :email, String, null: true

  def resolve(email:)
    auto_account_creation_enabled = AppConfigHelper.get_app_config(AppConfig::AUTO_ACCOUNT_CREATION_V1) == "1"

    if !current_user_is_logged_in?(context) && auto_account_creation_enabled
      existing_user = User.find_by(email: email)
      if existing_user
        raise GraphQL::ExecutionError, "Email has already been taken"
      end

      begin
        @user = UserFactoryService.call(
          email: email,
          role: User::ROLE_REGULAR_USER,
          send_activation: true,
          signup_path: User::SIGNUP_PATH[:self_registered]
        )
      rescue Auth0::Unsupported => e
        # Auth0 returns 409 when the email already exists in the tenant (present in Auth0 but not the
        # local DB). Surface the same graceful "already taken" GraphQL error as the local-dup case
        # above, rather than letting it bubble to GraphqlController#execute as an unhandled 500. (#384)
        raise e unless e.message.to_s.match?(/already exists/i)

        raise GraphQL::ExecutionError, "Email has already been taken"
      end
    else
      raise GraphQL::ExecutionError, "Permission denied"
    end
  end
end
