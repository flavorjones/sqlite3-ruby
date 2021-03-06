#ifndef SQLITE3_RUBY
#define SQLITE3_RUBY

#include <ruby.h>

#ifdef HAVE_RUBY_ENCODING_H
#include <ruby/encoding.h>

#define UTF8_P(_obj) (rb_enc_to_index(rb_enc_get(_obj)) == rb_enc_to_index(rb_utf8_encoding()))
#define UTF16_LE_P(_obj) (rb_enc_to_index(rb_enc_get(_obj)) == rb_enc_find_index("UTF-16LE"))
#define SQLITE3_UTF8_STR_NEW2(_obj) \
    (rb_enc_associate_index(rb_str_new2(_obj), rb_enc_to_index(rb_utf8_encoding())))

#else

#define SQLITE3_UTF8_STR_NEW2(_obj) (rb_str_new2(_obj))

#endif


#include <sqlite3.h>

extern VALUE mSqlite3;
extern VALUE cSqlite3Blob;

#include <database.h>
#include <statement.h>
#include <exception.h>

#endif
