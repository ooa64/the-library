
create table if not exists reader (
    name        varchar(100) primary key,
    state       varchar(10) default 'active' check (state in ('active','blocked')));
/
create table if not exists librarian (
    name        varchar(100) primary key);
/
-- NOTE: role sort order is significant: admin, librarian, reader
create view if not exists user (name,state,role) as
    select name,    state,    'reader'    from reader union all
    select name,    'active', 'librarian' from librarian union all
    select 'admin', 'active', 'admin';
/
create table if not exists book (
    id          integer primary key,
    title       varchar(100) not null,
    author      varchar(100) not null,
    publisher   varchar(100),
    published   date check (published is null or date(published) is not null));
/
create table if not exists request (
    id          integer primary key,
    bookid      integer unique references book(id),
    readername  varchar(100) not null references reader(name),
    -- readers request
    title       varchar(100) not null,
    author      varchar(100) not null,
    publisher   varchar(100),
    published   date check (published is null or date(published) is not null),
    -- current state
    returnterm  date check (returnterm is null or date(returnterm) is not null),
    returned    date check (returned is null or date(returned) is not null),
    state       varchar(10) generated always as (
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