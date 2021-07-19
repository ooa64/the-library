
create table if not exists reader (
    name        text primary key,
    state       text default 'active' check (state in ('active','blocked')),
    role        text generated always default 'reader');
/
create table if not exists librarian (
    name        text primary key,
    state       text generated always default 'active',
    role        text generated always default 'librarian');
/
-- NOTE: role sort order is significant: admin, librarian, reader
create view if not exists user (name, state, role) as
    select name,    state,    role    from reader union all
    select name,    state,    role    from librarian union all
    select 'admin', 'active', 'admin';
/
create table if not exists book (
    id          integer primary key,
    title       text not null,
    author      text not null,
    publisher   text,
    published   text check (published is null or date(published) is not null));
/
create table if not exists request (
    id          integer primary key,
    bookid      integer unique references book(id),
    readername  text not null references reader(name),
    -- readers request
    title       text not null,
    author      text not null,
    publisher   text,
    published   text check (published is null or date(published) is not null),
    -- current state
    returnterm  text check (returnterm is null or date(returnterm) is not null),
    returned    text check (returned is null or date(returned) is not null),
    state       text generated always as (
                case when (bookid is null and returnterm is null and returned is null) then 'requested'
                     when (bookid is null and returnterm is null and returned is not null) then 'returned'
                     when (bookid is null and returnterm is not null and returned is null) then 'lost'
                     when (bookid is null and returnterm is not null and returned is not null) then 'returned'
                     when (bookid is not null and returnterm is null and returned is null) then 'reading'
                     when (bookid is not null and returnterm is null and returned is not null) then 'invalid' -- 'librarian'
                     when (bookid is not null and returnterm is not null and returned is null) then 'abonement'
                     when (bookid is not null and returnterm is not null and returned is not null) then 'invalid' -- 'librarian'
                     else 'invalid' end) virtual check (state <> 'invalid'));
/
create trigger if not exists request_delete before delete on request
    when old.state <> 'requested'
    begin
        select raise(rollback,'wrong state');
    end;
/