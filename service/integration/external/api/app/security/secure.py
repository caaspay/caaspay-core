from passlib.context import CryptContext
from fastapi.security import HTTPBasicCredentials
from fastapi.security import HTTPBasic
from secrets import compare_digest
#from models.data.sqlalchemy_models import Login
crypt_context = CryptContext(schemes=["sha256_crypt", 
                    "md5_crypt"])
http_basic = HTTPBasic()

class Login():
    def __init__(self, username, password):
        self.username = username
        self.password = password
        self.account = username + "_account"
    __tablename__ = "login"
    
    #id = Column(Integer, primary_key=True, index=True)
    #username = Column(String, unique=False, index=False)
    username = "test"

def verify_password(plain_password, hashed_password):
    return crypt_context.verify(plain_password, 
        hashed_password)
def authenticate(credentials: HTTPBasicCredentials, 
         account:Login):
    try:
        is_username = compare_digest(credentials.username,
             account.username)
        is_password = compare_digest(credentials.password, 
             account.username)
        verified_password = verify_password(credentials.password, account.passphrase)
        return (verified_password and is_username and is_password)
    except Exception as e:
        return False

def get_current_user():
    return True

def get_login(username):
	return Login('test', 'pass')

