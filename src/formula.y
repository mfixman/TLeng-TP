%{
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include <assert.h>

// Operaciones posibles.
enum Operation
{
	Literal,
	Concat,
	Caretunder,
	Parentheses,
	Division
};

// El tamano de una expresion.
struct Size
{
	double x; // Ancho
	double ny, my; // Altura baja y altura alta.
};

// Una expresion.
struct Expression
{
	struct Expression *left, *right; // Expresiones hijos. Pueden ser NULL.
	char c; // Caracter que representa, si es de tipo Literal.

	enum Operation t; // Tipo de esta expresion.
	struct Size d; // Tamano de la expresion. Asignada por sizeExpression.
};

extern int yylex();
extern int yyparse();
extern char* yytext;

#define YYSTYPE_IS_DECLARED
typedef struct Expression *YYSTYPE;

YYSTYPE buildToken(char);
YYSTYPE buildExpression(enum Operation, YYSTYPE, YYSTYPE);
void sizeExpression(YYSTYPE);
void printExpression(YYSTYPE);
void printSVG(YYSTYPE);

void yyerror(const char *);
%}

%token T_DIV
%token T_CARET T_UNDER
%token T_OPENPAREN T_CLOSEPAREN T_OPENBRACKET T_CLOSEBRACKET
%token T_ID
%token T_ENDLINE

%start init

%%

init: e T_ENDLINE { sizeExpression($$); printSVG($$); }

e:	  f T_DIV e { $$ = buildExpression(Division, $1, $3); }
	| f

f:	  g f { $$ = buildExpression(Concat, $1, $2); }
	| g

g:	  h T_CARET h { $$ = buildExpression(Concat, $1, buildExpression(Caretunder, $3, NULL)); }
	| h T_UNDER h { $$ = buildExpression(Concat, $1, buildExpression(Caretunder, NULL, $3)); }
	| h T_CARET h T_UNDER h { $$ = buildExpression(Concat, $1, buildExpression(Caretunder, $3, $5)); }
	| h T_UNDER h T_CARET h { $$ = buildExpression(Concat, $1, buildExpression(Caretunder, $5, $3)); }
	| h

h:	  T_OPENPAREN e T_CLOSEPAREN { $$ = buildExpression(Parentheses, $2, NULL); }
	| T_OPENBRACKET e T_CLOSEBRACKET { $$ = $2; }
	| T_ID { $$ = buildToken(yytext[0]); }

%%

bool debug = false;

// Devuelve un nodo hoja, que tiene cierto caracter.
YYSTYPE buildToken(char c)
{
	YYSTYPE r = malloc(sizeof (struct Expression));
	r->c = c;
	r->t = Literal;
	r->left = r->right = NULL;

	return r;
}

// Devuelve una expresion representada por cierta operacion, y con dos hijos.
YYSTYPE buildExpression(enum Operation op, YYSTYPE left, YYSTYPE right)
{
	YYSTYPE r = malloc(sizeof (struct Expression));
	r->c = '\0';
	r->t = op;
	r->left = left;
	r->right = right;

	return r;
}

// Devuelve el tamano de un nodo que representa cierta operacion, y tiene
// ciertos hijos. Los hijos ya deben tener su tamano calculado.
struct Size getSizes(enum Operation t, YYSTYPE left, YYSTYPE right)
{
	switch (t)
	{
		case Literal:
			return (struct Size) {.x = 7, .ny = -6, .my = 0};

		case Concat:
			return (struct Size) {.x = left->d.x + right->d.x, .ny = fmin(left->d.ny, right->d.ny), .my = fmax(left->d.my, right->d.my)};

		case Caretunder:
		{
			struct Size r = {0, 0};
			if (left)
			{
				r.x = fmax(r.x, left->d.x * .75);
				r.ny = left->d.ny * .75 - 6;
			}
			if (right)
			{
				r.x = fmax(r.x, right->d.x * .75);
				r.my = right->d.my * .75 + 5;
			}
			return r;
		}

		case Parentheses:
			return (struct Size) {.x = left->d.x + 11, .ny = left->d.ny - 2, .my = left->d.my + 4};

		case Division:
			return (struct Size) {.x = fmax(left->d.x, right->d.x) * .8, .ny = left->d.ny * .8 - left->d.my - 4, .my = right->d.my * .8 - right->d.ny - 0.5};
	}

	fprintf(stderr, "Invalid operation under calculate: %d\n", t);
	exit(1);
}

// Calcula el tamano de los hijos de un nodo, y usa estos valores para
// asignarle un tamano a este nodo.
void sizeExpression(YYSTYPE q)
{
	if (q == NULL)
		return;

	sizeExpression(q->left);
	sizeExpression(q->right);

	q->d = getSizes(q->t, q->left, q->right);
}

// Imprime un nodo con cierta transformacion en x, y, y tamano.
void transformExpression(YYSTYPE q, double dx, double dy, double ds)
{
	if (q == NULL)
		return;

	printf("<g transform=\"translate(%lf %lf) scale(%lf)\">\n", dx, dy, ds);
	printExpression(q);
	printf("</g>\n");
}

// Imprime un nodo y sus hijos.
void printExpression(YYSTYPE q)
{
	if (q == NULL)
		return;

	switch (q->t)
	{
		case Literal:
			printf("<text>%c</text>\n", q->c);
			break;

		case Concat:
			printExpression(q->left);
			transformExpression(q->right, q->left->d.x, 0, 1);
			break;

		case Caretunder:
			transformExpression(q->left, 0, -6, .75);
			transformExpression(q->right, 0, 5, .75);
			break;

		case Parentheses:
		{
			double height = (q->d.my - q->d.ny) / 10;
			printf("<text transform=\"scale(1 %lf) translate(0 %lf)\">(</text>\n", height, height / 2);
			transformExpression(q->left, 6, 0, 1);
			printf("<text transform=\"scale(1 %lf) translate(%lf %lf)\">)</text>\n", height, q->left->d.x + 5, height / 2);
			break;
		}

		case Division:
			transformExpression(q->left, (q->d.x - q->left->d.x * .8) / 2, -q->left->d.my * .8 - 4, .8);
			printf("<line stroke-width=\"0.3\" stroke=\"black\" x1=\"0\" x2=\"%lf\" y1=\"-3\" y2=\"-3\" />\n", q->d.x);
			transformExpression(q->right, (q->d.x - q->right->d.x * .8) / 2, -q->right->d.ny * .8 - 0.5, .8);
			break;

		default:
			fprintf(stderr, "Invalid operation under print: %d\n", q->t);
			exit(1);
	}

	if (debug && q->t != Concat)
	{
		const char *colors[] = {"black", "red", "blue", "green", "purple"};

		printf("<line stroke-width=\".1\" stroke=\"%s\" x1=\"0\" x2=\"%lf\" y1=\"%lf\" y2=\"%lf\" />\n", colors[q->t], q->d.x, q->d.ny, q->d.ny);
		printf("<line stroke-width=\".1\" stroke=\"%s\" x1=\"0\" x2=\"%lf\" y1=\"%lf\" y2=\"%lf\" />\n", colors[q->t], q->d.x, q->d.my, q->d.my);
	}
}

// Imprime el SVG correspondiente a un arbol sintactico con raiz q. El tamano
// de q y sus hijos ya debe estar calculado.
void printSVG(YYSTYPE q)
{
	puts("<?xml version=\"1.0\" standalone=\"no\"?>");
	puts("<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">");
	puts("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\">");

	printf("<g transform=\"translate(50, %lf) scale(7)\" font-family=\"monospace\">\n", 300 - q->d.ny);

	printExpression(q);

	puts("</g>");
	puts("</svg>");
}

// Indica que hubo un error en el parseo.
void yyerror(const char* s)
{
	fprintf(stderr, "Parse error: %s\n", s);
	exit(1);
}

// Parsea la entrada, y activa el flag de debug si ese es el argumento.
int main(int argc, char *argv[])
{
	if (argc > 1 && !strcmp(argv[1], "--debug"))
		debug = true;

	yyparse();
}
