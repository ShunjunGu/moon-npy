// Byte-level lexer for the NPY header dictionary (plan §7.3).
//
// The header body is a restricted Python literal, e.g.
//   {'descr': '<f4', 'fortran_order': False, 'shape': (2, 3), }
// Per E3 the lexer scans ASCII byte-by-byte directly on Bytes and never
// converts the whole body to String; only an individual token's own span is
// materialized, decoded via @utf8.decode. Bytes::to_string must not be used
// here: it yields a debug repr like b"...", not the token's text.

///|
// One lexical token of the restricted header grammar. Package-private: only
// parse_header / NpyHeader are the header package's public surface (§10.1).
priv enum Token {
  LBrace // {
  RBrace // }
  LParen // (
  RParen // )
  Colon // :
  Comma // ,
  Str(String) // quoted string literal, surrounding quotes stripped
  KwTrue // True
  KwFalse // False
  Num(UInt64) // non-negative integer (a shape dimension)
  Eof // end of the header body span
}

// ASCII classifiers. Comparisons use Byte::to_int() codes (same style as
// format.mbt); the header is pure ASCII so there are no Unicode concerns.

///|
fn is_space(b : Byte) -> Bool {
  let c = b.to_int()
  c == 32 || c == 9 || c == 10 || c == 13 // ' ' \t \n \r
}

///|
fn is_digit(b : Byte) -> Bool {
  let c = b.to_int()
  c >= 48 && c <= 57 // '0'..'9'
}

///|
fn is_ident_start(b : Byte) -> Bool {
  let c = b.to_int()
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 // A-Z a-z _
}

///|
fn is_ident_char(b : Byte) -> Bool {
  is_ident_start(b) || is_digit(b)
}

///|
// Decode the byte span data[start..end) as UTF-8. The NPY header literal is
// ASCII in v1.0/v2.0 and UTF-8 in v3.0; both decode losslessly here. A span
// that is not valid UTF-8 cannot be part of a well-formed header, so it is
// rejected as InvalidHeaderSyntax rather than silently corrupted (decode, not
// decode_lossy — Correctness first).
fn decode_span(
  data : Bytes,
  start : Int,
  end : Int,
) -> Result[String, @error.NpyError] {
  try @utf8.decode(data.view(start~, end~)) |> Ok catch {
    _ => Err(@error.InvalidHeaderSyntax)
  }
}

///|
// Lex the header body span data[start..end) into a token stream terminated by
// Eof. Any byte that cannot begin a valid token, or an unterminated string
// literal, yields InvalidHeaderSyntax.
fn lex(
  data : Bytes,
  start : Int,
  end : Int,
) -> Result[Array[Token], @error.NpyError] {
  let toks : Array[Token] = Array::new()
  let mut i = start
  while i < end {
    let b = data[i]
    let c = b.to_int()
    if is_space(b) {
      i = i + 1
    } else if c == 123 {
      // '{'
      toks.push(LBrace)
      i = i + 1
    } else if c == 125 {
      // '}'
      toks.push(RBrace)
      i = i + 1
    } else if c == 40 {
      // '('
      toks.push(LParen)
      i = i + 1
    } else if c == 41 {
      // ')'
      toks.push(RParen)
      i = i + 1
    } else if c == 58 {
      // ':'
      toks.push(Colon)
      i = i + 1
    } else if c == 44 {
      // ','
      toks.push(Comma)
      i = i + 1
    } else if c == 39 || c == 34 {
      // '\'' or '"' : string literal; scan to the matching quote
      let quote = c
      let content0 = i + 1
      let mut j = content0
      let mut closed = false
      while j < end && !closed {
        if data[j].to_int() == quote {
          closed = true
        } else {
          j = j + 1
        }
      }
      if !closed {
        return Err(@error.InvalidHeaderSyntax)
      }
      match decode_span(data, content0, j) {
        Err(e) => return Err(e)
        Ok(s) => toks.push(Str(s))
      }
      i = j + 1
    } else if is_digit(b) {
      // non-negative integer; accumulated in UInt64 (dims are UInt64, §9.2)
      let mut n = 0UL
      let mut j = i
      while j < end && is_digit(data[j]) {
        n = n * 10UL + (data[j].to_int() - 48).to_uint64()
        j = j + 1
      }
      toks.push(Num(n))
      i = j
    } else if is_ident_start(b) {
      // only the two booleans are valid bare words in the header
      let word0 = i
      let mut j = i
      while j < end && is_ident_char(data[j]) {
        j = j + 1
      }
      match decode_span(data, word0, j) {
        Err(e) => return Err(e)
        Ok(word) =>
          if word == "True" {
            toks.push(KwTrue)
          } else if word == "False" {
            toks.push(KwFalse)
          } else {
            return Err(@error.InvalidHeaderSyntax)
          }
      }
      i = j
    } else {
      return Err(@error.InvalidHeaderSyntax)
    }
  }
  toks.push(Eof)
  Ok(toks)
}
