#!/usr/bin/env python3

from datetime import date
from urllib.parse import urlparse, parse_qsl, unquote_plus
from http.server import HTTPServer, BaseHTTPRequestHandler
from http.cookies import SimpleCookie

DBFILE = "library.db"
DBSCHEMA = "library.sql"
PAGEROOT = "pages"
HTTPPORT = 9999
DEBUG = 0


class Handler(BaseHTTPRequestHandler):

    def do_GET(self):
        try:
            api, params = parse_path(self.path)

            cookies = SimpleCookie(self.headers.get("Cookie"))
            if not "libraryuser" in cookies:
                self.send_file("login")
                return

            username = parse_user(cookies["libraryuser"].value)
            userstate = get_state(username)
            if (userstate == ""):
                new_user(username)
                userstate = get_state(username)
            if (userstate == "blocked"):
                self.send_file("login")
                return

            userrole = get_role(username)

            if api == "/":
                self.send_file(userrole)
            else:
                self.send_api(api, username, userrole, params)

        except Exception as e:
            self.log_error('"ERROR" %s', e)
            if DEBUG:
                import traceback
                self.log_error('"TRACE" %s', ''.join(traceback.format_tb(e.__traceback__)))
            try:
                self.send(500, "text/plain", str(e))
            except Exception as e:
                print("SEND ERROR", e)


    def send_file(self, basename):
        self.log_message('"PAGE %s', f"{PAGEROOT}/{basename}.html")
        self.send(200, "text/html", read_file(f"{PAGEROOT}/{basename}.html"))

    def send_api(self, api, username, userrole, params):
        self.log_message('"CALL %s %s/%s" %s', api.__name__, username, userrole, params)
        self.send(200, "application/json", api(username, userrole, params))

    def send(self, code, contenttype, content):
        c = content.encode()
        self.send_response(code)
        self.send_header("Connection", "close")
        self.send_header("Content-Type", contenttype)
        self.send_header("Content-Length", len(c))
        self.end_headers()
        self.wfile.write(c)


USER = ["name", "role", "state"]
BOOK = ["id", "title", "author", "publisher", "published"]
REQUEST = ["id", "bookid", "readername", "title", "author",
           "publisher", "published", "returnterm", "returned", "state"]


def start():
    global server
    init(DBSCHEMA, DBFILE)
    server = HTTPServer(("", HTTPPORT), Handler).serve_forever()


def stop():
    server.shutdown()
    server.server_close()
    done()


def init(dbschema, dbfile):
    import sqlite3
    global db
    db = sqlite3.connect(dbfile, isolation_level=None)
    db.execute("PRAGMA foreign_keys=1")
    db.execute("PRAGMA encoding=\"UTF-8\"")
    for s in read_file(dbschema).split("/"):
        db.execute(s)
    # if DEBUG:
    #     db.set_trace_callback(print)


def done():
    db.close()


def read_file(filename):
    with open(filename, "r") as f:
        return f.read()


def parse_path(path):
    p = urlparse(path)
    if p.path in ["", "/"]:
        return "/", {}
    if p.path[0] == "/":
        n = f"api_{p.path[1:]}"
        if n in globals():
            return globals()[n], dict(parse_qsl(p.query))
    raise Exception('bad request')


def parse_user(user):
    return unquote_plus(user)

def new_user(username):
    db.execute("insert into reader(name) values(?)", [username])


def get_role(username):
    s = "select role from user where state = 'active' and name = ? order by role"
    r = db.execute(s, [username]).fetchone()
    return "" if r == None else r[0]


def get_state(username):
    s = "select state from user where name = ? order by role"
    r = db.execute(s, [username]).fetchone()
    return "" if r == None else r[0]


### API Helpers ###


def prepare_where(props):
    return "true " + " ".join(map(lambda x: f"and {x}=:{x}", props))


def prepare_json(props):
    return ",".join(map(lambda x: f"'{x}',{x}", props))


def prepare_update(props):
    return ",".join(map(lambda x: f"{x}=:{x}", props))


def prepare_values(props):
    return ",".join(map(lambda x: f":{x}", props))

  
def prepare_select(props):
    return ",".join(props)


def filter_props(params, props):
    return list(filter(lambda f: f in params, props))


def check_props(params, props):
    p = filter_props(params, props)
    if len(p) > 0:
        return p
    raise Exception('no data')


def check_role(role, permits):
    if role in permits:
        return role
    raise Exception('forbidden')


def query_onecolumn(sql, params):
    if DEBUG:
        from sys import stderr
        stderr.write("SQL: %s\n" % sql)
        stderr.write("VAR: %s\n" % params)
    r = db.execute(sql, params).fetchone()
    return "" if r == None else r[0]


def query_object(props, sql, params):
    s = f"select json_object({prepare_json(props)}) json from ({sql})"
    return query_onecolumn(s, params)


def query_array(props, sql, params):
    s = f"select json_group_array(json_object({prepare_json(props)})) json from ({sql})"
    return query_onecolumn(s, params)


def query_update(props, sql, params):
    # NOTE: omit returning clause due to the newest sqlite requirements
    # s = f"{sql} returning json_object({prepare_json(props)})"
    s = sql
    return query_onecolumn(s, params)


### API ###    


def api_getuser(username, userrole, params):
    check_role(userrole, ["admin", "librarian", "reader"])
    return query_object(USER, "select * from user where name=:name", {"name":username})


def api_getusers(username, userrole, params):
    check_role(userrole, ["admin", "librarian"])
    w = prepare_where(filter_props(params, ["name", "role", "state"]))
    return query_array(USER, f"select * from user where {w} order by name,role", params)


def api_setreader(username, userrole, params):
    check_role(userrole, ["admin"])
    check_props(params, ["state"])
    check_props(params, ["name"])
    return query_update(USER, "update reader set state=:state where name=:name", params)


def api_addlibrarian(username, userrole, params):
    check_role(userrole, ["admin"])
    check_props(params, ["name"])
    return query_update(USER, "insert into librarian(name) values(:name)", params)


def api_dellibrarian(username, userrole, params):
    check_role(userrole, ["admin"])
    check_props(params, ["name"])
    return query_update(USER, "delete from librarian where name=:name", params)


def api_getbooks(username, userrole, params):
    check_role(userrole, ["admin","librarian"])
    if "inuse" in params:
        # WORKAROUND: sqlite 3.36.0 needs native number for 'inuse'
        params["inuse"] = int(params["inuse"])
    p = filter_props(params, ["id","title","author","publisher","published","inuse"])
    w = prepare_where(p)
    return query_array(BOOK+["inuse"], f"""
        with bookinuse as (
            select book.*,
                (select count(*) from request where bookid = book.id) inuse
            from book)
        select * from bookinuse where {w} order by id
    """, params)


def api_querybooks(username, userrole, params):
    f = ["title","author","publisher","published"]
    p = filter_props(params, ["title","author"])
    s = prepare_select(f)
    w = prepare_where(p)
    o = ""
    if "order" in params and params["order"] in f:
        o = f" order by {params['order']}"
        if "reverse" in params and int(params["reverse"]):
            o += " desc"
    return query_array(f, f"select distinct {s} from book where {w}{o}", params)


def api_setbook(username, userrole, params):
    check_role(userrole, ["admin"])
    p = check_props(params, ["id","title","author","publisher","published"])
    s = prepare_select(p)
    v = prepare_values(p)
    return query_update(BOOK, f"insert or replace into book({s}) values({v})", params)


def api_delbook(username, userrole, params):
    check_role(userrole, ["admin"])
    check_props(params, ["id"])
    return query_update(BOOK, f"delete from book where id=:id", params)


def api_addrequest(username, userrole, params):
    check_role(userrole, ["reader"])
    p = check_props(params, ["title","author","publisher","published"])
    s = prepare_select(p)
    v = prepare_values(p)
    params["readername"] = username
    return query_update(REQUEST, f"insert into request(readername,{s}) values(:readername,{v})", params)


def api_setrequest(username, userrole, params):
    check_role(userrole, ["librarian"])
    check_props(params, ["id"])
    p = check_props(params, ["bookid","returnterm"])
    u = prepare_update(p)
    return query_update(REQUEST, f"update request set {u} where id=:id", params)


def api_delrequest(username, userrole, params):
    check_role(userrole, ["librarian","reader"])
    p = check_props(params, ["id"])
    if userrole == "reader":
        params["readername"] = username
        p.append("readername")
    w = prepare_where(p)
    return query_update(REQUEST, f"delete from request where {w}", params)


def api_getrequests(username, userrole, params):
    check_role(userrole, ["librarian","reader"])
    p = filter_props(params, ["state"])
    if userrole == "reader":
        p.append("readername")
        params["readername"] = username
    elif "readername" in params:
        p.append("readername")
    w = prepare_where(p)
    return query_array(REQUEST, f"select * from request where {w} order by id", params)


def api_closerequest(username, userrole, params):
    check_role(userrole, ["librarian"])
    check_props(params, ["id"])
    return query_update(REQUEST, f"update request set bookid=null,returned='{date.today():%Y-%m-%d}' where id=:id", params)


if __name__ == "__main__":
    print(f"Starting Server on port {HTTPPORT}")
    start()
