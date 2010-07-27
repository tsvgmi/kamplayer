# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_vidkar_session',
  :secret      => '79f476f8725fa11ed0cda4212822ca6257a1734c9759034a3c0d327ceea3e7af878a9aeeda556ea896541811a67c141f8052c71463d2b05d583449daa2e95e22'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
