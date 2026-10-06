import os, sys
APP = os.environ.get("APP_DIR", "/workspace/app")
sys.path.insert(0, APP); os.chdir(APP)
import snowflake.connector
from snowflake.snowpark import Session
CFG = dict(account=os.environ["SNOWFLAKE_ACCOUNT"], host=os.environ["SNOWFLAKE_HOST"], authenticator="oauth",
           token=open(os.environ["SNOWFLAKE_TOKEN_FILE_PATH"]).read().strip(), warehouse="Z21_WH", role=os.environ.get("TEST_ROLE", "ACCOUNTADMIN"))
raw = snowflake.connector.connect(**CFG)
s = Session.builder.configs(CFG).create()
class FakeConn:
    def query(self, sql, ttl=0):
        cur = raw.cursor(); cur.execute(sql); return cur.fetch_pandas_all()
    def session(self): return s
import streamlit as st
st.connection = lambda *a, **k: FakeConn()
_sb = st.selectbox
st.segmented_control = lambda label, options, default=None, **k: _sb(
    label, options, index=options.index(default) if default in options else 0, key=k.get("key"))
from streamlit.testing.v1 import AppTest
PAGES = ["command_center", "delivery", "inventory", "suppliers", "what_if", "actions", "trust", "operations"]
def new(path):
    at = AppTest.from_file(path, default_timeout=240)
    at.session_state["conn"] = FakeConn(); at.session_state["persona"] = "Planning"
    return at
def errors(at):
    return [c.value[:300] for c in at.code] + [str(x.value)[:300] for x in at.exception]
