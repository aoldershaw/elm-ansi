module Ansi (Color(..), Action(..), parse) where

{-| This library primarily exposes the `parse` function and the types that it
will yield.

@docs parse

@docs Action, Color
-}

import Char
import String

{-| The events relevant to interpreting the stream.

* `SetForeground` corresponds to `\e[3Xm` and `\e[4Xm` where X is the color
* `SetBackground` corresponds to `\e[9Xm` and `\e[10Xm` where X is the color
* `SetBold` corresponds to `\e[1m`
* `SetFaint` corresponds to `\e[2m`
* `SetItalic` corresponds to `\e[3m`
* `SetUnderline` corresponds to `\e[4m`
* `SetInverted` corresponds to `\e[7m`
* `Linebreak` corresponds to a `\n` character
* `CarriageReturn` corresponds to a `\r` character
* `Print` is a chunk of text which should be interpreted with the style implied
  by the preceding actions (i.e. `[Bold True, Print "foo"]`) should yield a bold
  `foo`
* `Remainder` is a partial ANSI escape sequence, returned at the end of the
  actions if it was cut off. The next string passed to `parse` should have this
  prepended to it.
-}
type Action
  = SetForeground (Maybe Color)
  | SetBackground (Maybe Color)
  | SetBold Bool
  | SetFaint Bool
  | SetItalic Bool
  | SetUnderline Bool
  | SetInverted Bool
  | Linebreak
  | CarriageReturn
  | Print String
  | Remainder String

{-| The colors applied to the foreground/background.
-}
type Color
  = Black
  | Red
  | Green
  | Yellow
  | Blue
  | Magenta
  | Cyan
  | White
  | BrightBlack
  | BrightRed
  | BrightGreen
  | BrightYellow
  | BrightBlue
  | BrightMagenta
  | BrightCyan
  | BrightWhite

{-| Convert an arbitrary String of text into a sequence of actions.

If the input string ends with a partial ANSI escape sequence, it will be
yielded as a `Remainder` action, which should then be prepended to the next
call to `parse`.
-}
parse : String -> List Action
parse = parseChars << String.toList

parseChars : List Char -> List Action
parseChars seq =
  case seq of
    '\r' :: cs ->
      CarriageReturn :: parseChars cs

    '\n' :: cs ->
      Linebreak :: parseChars cs

    '\x1b' :: '[' :: cs ->
      case collectCodes cs of
        Incomplete ->
          [Remainder (String.fromList seq)]

        Invalid ->
          parseChars cs

        SetSGR codes rest ->
          (List.concatMap codeActions codes) ++ parseChars rest

    ['\x1b'] -> [Remainder (String.fromList seq)]

    c :: cs ->
      let
        rest = parseChars cs
      in
        case rest of
          Print s :: actions ->
            Print (String.cons c s) :: actions

          actions ->
            Print (String.fromChar c) :: actions

    [] ->
      []

type CodeParseResult
  = Incomplete
  | Invalid
  | SetSGR (List Int) (List Char)

collectCodes : List Char -> CodeParseResult
collectCodes seq = collectCodesMemo seq [] ""

collectCodesMemo : List Char -> (List Int) -> String -> CodeParseResult
collectCodesMemo seq codes currentNum =
  case seq of
    'm' :: cs ->
      case String.toInt currentNum of
        Ok num -> SetSGR (codes ++ [num]) cs
        Err _ -> Invalid -- TODO handle \e[m same as \e[0m

    ';' :: cs ->
      case String.toInt currentNum of
        Ok num -> collectCodesMemo cs (codes ++ [num]) ""
        Err _ -> Invalid

    c :: cs ->
      if Char.isDigit c
         then collectCodesMemo cs codes (currentNum ++ String.fromChar c)
         else Invalid

    [] ->
      Incomplete

codeActions : Int -> List Action
codeActions code =
  case code of
    0 -> reset
    1 -> [SetBold True]
    2 -> [SetFaint True]
    3 -> [SetItalic True]
    4 -> [SetUnderline True]
    7 -> [SetInverted True]
    30 -> [SetForeground (Just Black)]
    31 -> [SetForeground (Just Red)]
    32 -> [SetForeground (Just Green)]
    33 -> [SetForeground (Just Yellow)]
    34 -> [SetForeground (Just Blue)]
    35 -> [SetForeground (Just Magenta)]
    36 -> [SetForeground (Just Cyan)]
    37 -> [SetForeground (Just White)]
    40 -> [SetBackground (Just Black)]
    41 -> [SetBackground (Just Red)]
    42 -> [SetBackground (Just Green)]
    43 -> [SetBackground (Just Yellow)]
    44 -> [SetBackground (Just Blue)]
    45 -> [SetBackground (Just Magenta)]
    46 -> [SetBackground (Just Cyan)]
    47 -> [SetBackground (Just White)]
    90 -> [SetForeground (Just BrightBlack)]
    91 -> [SetForeground (Just BrightRed)]
    92 -> [SetForeground (Just BrightGreen)]
    93 -> [SetForeground (Just BrightYellow)]
    94 -> [SetForeground (Just BrightBlue)]
    95 -> [SetForeground (Just BrightMagenta)]
    96 -> [SetForeground (Just BrightCyan)]
    97 -> [SetForeground (Just BrightWhite)]
    100 -> [SetBackground (Just BrightBlack)]
    101 -> [SetBackground (Just BrightRed)]
    102 -> [SetBackground (Just BrightGreen)]
    103 -> [SetBackground (Just BrightYellow)]
    104 -> [SetBackground (Just BrightBlue)]
    105 -> [SetBackground (Just BrightMagenta)]
    106 -> [SetBackground (Just BrightCyan)]
    107 -> [SetBackground (Just BrightWhite)]
    _ -> []

reset : List Action
reset =
  [ SetForeground Nothing
  , SetBackground Nothing
  , SetBold False
  , SetFaint False
  , SetItalic False
  , SetUnderline False
  , SetInverted False
  ]
