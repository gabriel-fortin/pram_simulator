
%<Header>


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Definitions.
%<Macro Definitions>

WS = ([\n\s\t]*)
LETTER = ([_a-zA-ZąćęłóśżźĄĆĘŁÓŚŻŹ])


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Rules.
%<Token Rules>


%%%  whitespace
[\n\s\t]+ : skip_token.


%%%  comment
//[^\n]*\n : skip_token.



%%%  numbers
[0-9]+ : {token, {positive_integer, TokenLine, list_to_integer(TokenChars)}}.
% floats?


%%%  booleans
true  : {token, {boolean, TokenLine, true}}.
false : {token, {boolean, TokenLine, false}}.



%%%  plain types
int  : {token, {simple_type, TokenLine, int}}.
bool : {token, {simple_type, TokenLine, bool}}.
void : {token, {void, TokenLine}}.
% floats?
% chars?



%%%  "punctuation", operators
;    : {token, {';', TokenLine}}.
':'  : {token, {':', TokenLine}}.
,    : {token, {',', TokenLine}}.

\[   : {token, {'[', TokenLine}}.
\]   : {token, {']', TokenLine}}.

\{   : {token, {'{', TokenLine}}.
\}   : {token, {'}', TokenLine}}.

\(   : {token, {'(', TokenLine}}.
\)   : {token, {')', TokenLine}}.
\.\. : {token, {'..', TokenLine}}.

=    : {token, {'=', TokenLine}}.

<    : {token, {'<', TokenLine}}.
>    : {token, {'>', TokenLine}}.
<=   : {token, {'<=', TokenLine}}.
>=   : {token, {'>=', TokenLine}}.
==   : {token, {'==', TokenLine}}.
!=   : {token, {'!=', TokenLine}}.

&&   : {token, {'&&', TokenLine}}.
\|\| : {token, {'||', TokenLine}}.

!    : {token, {'!', TokenLine}}.

% implementing inc/dec operators may be tricky so it's left for another time   TODO
% \+\+ : {token, {'++', TokenLine}}.
% --   : {token, {'--', TokenLine}}.

\+   : {token, {'+', TokenLine}}.
-    : {token, {'-', TokenLine}}.
\*   : {token, {'*', TokenLine}}.
/    : {token, {'/', TokenLine}}.
<<   : {token, {'<<', TokenLine}}.
>>   : {token, {'>>', TokenLine}}.



%%%  keywords
load : {token, {load, TokenLine}}.
(input|output|const) : {token, {var_modifier, TokenLine, list_to_atom(TokenChars)}}.
pardo : {token, {pardo, TokenLine}}.
if : {token, {'if', TokenLine}}.
else : {token, {else, TokenLine}}.
while : {token, {while, TokenLine}}.
for : {token, {for, TokenLine}}.
(break|continue) : {token, {loop_ctrl, TokenLine, list_to_atom(TokenChars)}}.
return : {token, {return, TokenLine}}.



%%%  user defined symbol
{LETTER}({LETTER}|[0-9])* : {token, {user_symbol, TokenLine, TokenChars}}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Erlang code.
%<Erlang code>


