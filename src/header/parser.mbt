// Recursive-descent parser: token stream -> NpyHeader (plan §7.3, §9.1).
//
// Grammar (restricted Python literal):
//   header := "{" entries "}"
//   entry  := string ":" value
//   value  := string | bool | tuple
//   tuple  := "(" integer_list ")"   // shape; allows () and a trailing comma
//   bool   := "True" | "False"       // fortran_order
//
// M1 recognizes exactly the three NumPy keys (descr / fortran_order / shape).
// Unknown keys and missing keys are rejected rather than ignored, because the
// Oracle treats the header as a closed set (§12 MissingHeaderField). `descr`
// stays a raw String here; the M2 dtype layer parses it and enforces the
// object-array security boundary (§5).

///|
// Parse a complete NPY file's header dictionary from raw bytes. The header body
// span is located via format.parse_prefix (trusting only header_len, so no
// 64-byte-alignment assumption, §7.4), lexed, then reduced to NpyHeader.
pub fn parse_header(data : Bytes) -> Result[NpyHeader, @error.NpyError] {
  match @format.parse_prefix(data) {
    Err(e) => Err(e)
    Ok(prefix) => {
      let start = prefix.header_start
      let end = prefix.data_offset.to_int()
      match lex(data, start, end) {
        Err(e) => Err(e)
        Ok(toks) => parse_tokens(toks)
      }
    }
  }
}

// Safe cursor read: past the last token behaves as Eof so malformed input
// reports a syntax error instead of trapping on an out-of-range index.

///|
fn peek(toks : Array[Token], p : Int) -> Token {
  if p < toks.length() {
    toks[p]
  } else {
    Eof
  }
}

// Reduce the token stream to NpyHeader. `p` is a cursor advanced in place.

///|
fn parse_tokens(toks : Array[Token]) -> Result[NpyHeader, @error.NpyError] {
  let mut p = 0
  match peek(toks, p) {
    LBrace => p = p + 1
    _ => return Err(@error.InvalidHeaderSyntax)
  }
  let mut descr : String = ""
  let mut fortran = false
  let shape : Array[UInt64] = Array::new()
  let mut seen_descr = false
  let mut seen_fortran = false
  let mut seen_shape = false
  let mut done = false
  while !done {
    match peek(toks, p) {
      RBrace => {
        p = p + 1
        done = true
      }
      Str(key) => {
        p = p + 1
        match peek(toks, p) {
          Colon => p = p + 1
          _ => return Err(@error.InvalidHeaderSyntax)
        }
        if key == "descr" {
          match peek(toks, p) {
            Str(v) => {
              descr = v
              seen_descr = true
              p = p + 1
            }
            _ => return Err(@error.InvalidHeaderSyntax)
          }
        } else if key == "fortran_order" {
          match peek(toks, p) {
            KwTrue => {
              fortran = true
              seen_fortran = true
              p = p + 1
            }
            KwFalse => {
              fortran = false
              seen_fortran = true
              p = p + 1
            }
            _ => return Err(@error.InvalidHeaderSyntax)
          }
        } else if key == "shape" {
          match peek(toks, p) {
            LParen => p = p + 1
            _ => return Err(@error.InvalidHeaderSyntax)
          }
          // integer list; accept () and a trailing comma like NumPy's (3,)
          let mut tup_done = false
          while !tup_done {
            match peek(toks, p) {
              RParen => {
                p = p + 1
                tup_done = true
              }
              Num(n) => {
                shape.push(n)
                p = p + 1
                match peek(toks, p) {
                  Comma => p = p + 1
                  _ => ()
                }
              }
              _ => return Err(@error.InvalidHeaderSyntax)
            }
          }
          seen_shape = true
        } else {
          return Err(@error.InvalidHeaderSyntax) // unknown key
        }
        // a value is followed by ',' or the closing '}'
        match peek(toks, p) {
          Comma => p = p + 1
          RBrace => ()
          _ => return Err(@error.InvalidHeaderSyntax)
        }
      }
      _ => return Err(@error.InvalidHeaderSyntax) // Eof or stray token: no '}'
    }
  }
  match peek(toks, p) {
    Eof => ()
    _ => return Err(@error.InvalidHeaderSyntax) // trailing junk after '}'
  }
  if !seen_descr {
    return Err(@error.MissingHeaderField("descr"))
  }
  if !seen_fortran {
    return Err(@error.MissingHeaderField("fortran_order"))
  }
  if !seen_shape {
    return Err(@error.MissingHeaderField("shape"))
  }
  Ok(NpyHeader::{ descr, shape, fortran_order: fortran, })
}
