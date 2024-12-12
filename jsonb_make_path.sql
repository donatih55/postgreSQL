/*
When working with JSONB, one may often want to manipulate complex objects but unfortunatly, jsonb_set only works with already existing nodes (unless you don;t mind overwriting its siblings...). 
I created this to ensure a path in the JSON exists before calling an update statement with jsonb_set. 

E.g. You have a table: 
create table settings (
  id serial primary key
  , settings jsonb
);

The data in it may be something like:
insert into settings (id, settings) select 1, '{"User" : {}}'::jsonb;

Now, sometime later you want to set settings to be something like this json:
{
  "User" : {
    "Favs" : {
      "sites" : []
    }
  }
}

You can't with just a simple set_jsonb... You can definetly overwrite the whole column, but I'm lazy and want to use the same logic on my app over and over again instead of adding if/elses all around to see if certain properties exist. 

Feels like a lot, but you could do this: 

call jsonb_make_path('User,Favs,sites', 'public', 'settings', 'settings', 'id = 1');
update "public"."settings"
set "settings" = jsonb_set(
  settings
  , 'User,Favs,sites'
  , '[]'::jsonb
  , true
)

In my case, I made the above be a procedure of itself so my API only has to pass in the path and the new value.

Hope this helps somebody someday :)

PS: if anyone wants to rewrite this using a Format and using optional param to the execute, be my guest - and tag me after too so I can post the link here as a better solution!

*/


create or replace procedure jsonb_make_path (_path varchar, _table_schema varchar, _table_name varchar, _table_column varchar, _where_criteria varchar)
language plpgsql
as $$
declare 
    _lastNode varchar;
    _tempPath varchar;
    _t bool;
BEGIN
    execute (
            'select 
                jsonb_path_exists(
                    ' ||  quote_ident(_table_column) || '
                    , replace(''$.'|| _path ||''', '','',''.'')::jsonpath
                ) 
            from 
             ' || quote_ident( _table_schema) || '.' ||  quote_ident(_table_name) || '
            where '
                || _where_criteria
        ) into _t;
    --if the node exists already, do nothing
    if NOT _t
    then
        --if NOT primary node on path, recurse
        if _path like '%,%' then
            --figure out the path for the previous node
            _lastNode = reverse(split_part(reverse(_path), ',', 1));
            _tempPath = substring(_path from 1 for length(_path) - length(_lastNode) - 1 );

             --recurse until previous path is created
            call jsonb_make_path(_tempPath, _table_schema, _table_name, _table_column, _where_criteria);

        end if;

        --after recursing (or once finding the first node alterady that exists / primary node), create the new node
        --PSin place for null cols
       execute (
            'update ' || quote_ident( _table_schema) || '.' ||  quote_ident(_table_name) || ' 
                set ' || quote_ident( _table_column)|| ' = 
                    jsonb_set (
                        coalesce(' 
                            || quote_ident( _table_column)  || ', ''{}''::jsonb
                        )
                        , (''{' || _path || '}'')::text[]
                        , ''{}''::jsonb
                        , true 
                    ) 
            where ' || _where_criteria
        );
    end if;
end $$;
