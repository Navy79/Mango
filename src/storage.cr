require "sqlite3"
require "crypto/bcrypt"
require "uuid"
require "base64"

def hash_password(pw)
	Crypto::Bcrypt::Password.create(pw).to_s
end

def verify_password(hash, pw)
	(Crypto::Bcrypt::Password.new hash).verify pw
end

def random_str
	Base64.strict_encode UUID.random().to_s
end

class Storage
	property path : String

	def initialize(path)
		@path = path
		dir = File.dirname path
		unless Dir.exists? dir
			Dir.mkdir_p dir
		end
		DB.open "sqlite3://#{path}" do |db|
			begin
				db.exec "create table users" \
					"(username text, password text, token text, admin integer)"
			rescue e : SQLite3::Exception | DB::Error
				unless e.message == "table users already exists"
					raise e
				end
			else
				db.exec "create unique index username_idx on users (username)"
				db.exec "create unique index token_idx on users (token)"
				random_pw = random_str
				hash = hash_password random_pw
				db.exec "insert into users values (?, ?, ?, ?)",
					"admin", hash, nil, 1
				puts "Initial user created. You can log in with " \
					"#{{"username" => "admin", "password" => random_pw}}"
			end
		end
	end

	def verify_user(username, password)
		DB.open "sqlite3://#{@path}" do |db|
			begin
				hash, token = db.query_one "select password, token from "\
					"users where username = (?)", \
					username, as: {String, String?}
				unless verify_password hash, password
					return nil
				end
				return token if token
				token = random_str
				db.exec "update users set token = (?) where username = (?)",
					token, username
				return token
			rescue e : SQLite3::Exception | DB::Error
				return nil
			end
		end
	end

	def verify_token(token)
		DB.open "sqlite3://#{@path}" do |db|
			begin
				username = db.query_one "select username from users where " \
					"token = (?)", token, as: String
				return username
			rescue e : SQLite3::Exception | DB::Error
				return nil
			end
		end
	end

	def verify_admin(token)
		DB.open "sqlite3://#{@path}" do |db|
			begin
				return db.query_one "select admin from users where " \
					"token = (?)", token, as: Bool
			rescue e : SQLite3::Exception | DB::Error
				return false
			end
		end
	end

	def list_users
		results = Array(Tuple(String, Bool)).new
		DB.open "sqlite3://#{@path}" do |db|
			db.query "select username, admin from users" do |rs|
				rs.each do
					results << {rs.read(String), rs.read(Bool)}
				end
			end
		end
		results
	end

	def new_user(username, password, admin)
		admin = (admin ? 1 : 0)
		DB.open "sqlite3://#{@path}" do |db|
			hash = hash_password password
			db.exec "insert into users values (?, ?, ?, ?)",
				username, hash, nil, admin
		end
	end

	def update_user(original_username, username, password, admin)
		admin = (admin ? 1 : 0)
		DB.open "sqlite3://#{@path}" do |db|
			if password.size == 0
				db.exec "update users set username = (?), admin = (?) "\
					"where username = (?)",\
					username, admin, original_username
			else
				hash = hash_password password
				db.exec "update users set username = (?), admin = (?),"\
					"password = (?) where username = (?)",\
					username, admin, hash, original_username
			end
		end
	end

	def delete_user(username)
		DB.open "sqlite3://#{@path}" do |db|
			db.exec "delete from users where username = (?)", username
		end
	end

	def logout(token)
		DB.open "sqlite3://#{@path}" do |db|
			begin
				db.exec "update users set token = (?) where token = (?)", \
					nil, token
			rescue
			end
		end
	end
end
