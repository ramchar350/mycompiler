/*
 * CS250
 *
 * simple.y: simple parser for the simple "C" language
 * 
 * (C) Copyright Gustavo Rodriguez-Rivera grr@purdue.edu
 *
 * IMPORTANT: Do not post in Github or other public repository
 */

%token	<string_val> WORD

%token 	NOTOKEN LPARENT RPARENT LBRACE RBRACE LCURLY RCURLY COMA SEMICOLON EQUAL STRING_CONST LONG LONGSTAR VOID CHARSTAR CHARSTARSTAR INTEGER_CONST AMPERSAND OROR ANDAND EQUALEQUAL NOTEQUAL LESS GREAT LESSEQUAL GREATEQUAL PLUS MINUS TIMES DIVIDE PERCENT IF ELSE WHILE DO FOR CONTINUE BREAK RETURN

%union	{
		char   *string_val;
		int nargs;
		int my_nlabel;
	}

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

int yylex();
int yyerror(const char * s);

extern int line_number;
const char * input_file;
char * asm_file;
FILE * fasm;

#define MAX_ARGS 5
int nargs;
char * args_table[MAX_ARGS];

#define MAX_GLOBALS 100
int nglobals = 0;
char * global_vars_table[MAX_GLOBALS];
int global_vars_type[MAX_GLOBALS];

#define MAX_LOCALS 32
int nlocals = 0;
char * local_vars_table[MAX_LOCALS];
int local_vars_type[MAX_LOCALS];

#define MAX_LOOP 100
int loop_labels[MAX_LOOP];
int loop_depth = 0;
int continue_labels[MAX_LOOP];

#define MAX_STRINGS 100
int nstrings = 0;
char * string_table[MAX_STRINGS];

char *regStk[]={ "rbx", "r10", "r13", "r14", "r15"};
char nregStk = sizeof(regStk)/sizeof(char*);

char *regArgs[]={ "rdi", "rsi", "rdx", "rcx", "r8", "r9"};
char nregArgs = sizeof(regArgs)/sizeof(char*);

int current_type = 0;

int top = 0;

int nargs = 0;
 
int nlabel = 0;

int loopConditional = 0;

int locals = 0;
int localvar = -1;

%}

%%

goal:	program
	;

program :
        function_or_var_list;

function_or_var_list:
        function_or_var_list function
        | function_or_var_list global_var
        | /*empty */
	;

function:
         var_type WORD
         {
		 locals = 0;
		 nlocals = 0;
		 fprintf(fasm, "\t.text\n");
		 fprintf(fasm, ".globl %s\n", $2);
		 fprintf(fasm, "%s:\n", $2);

		 fprintf(fasm, "\t# Save Frame pointer\n");
		 fprintf(fasm, "\tpushq %%rbp\n");
                 fprintf(fasm, "\tmovq %%rsp,%%rbp\n");

		 fprintf(fasm, "\tsubq $%d, %%rsp\n", MAX_LOCALS * 8);
		 fprintf(fasm, "# Save registers. \n");
		 fprintf(fasm, "# Push one extra to align stack to 16bytes\n");
                 fprintf(fasm, "\tpushq %%rbx\n");
		 fprintf(fasm, "\tpushq %%rbx\n");
		 fprintf(fasm, "\tpushq %%r10\n");
		 fprintf(fasm, "\tpushq %%r13\n");
		 fprintf(fasm, "\tpushq %%r14\n");
		 fprintf(fasm, "\tpushq %%r15\n");

	 }
	 LPARENT arguments RPARENT compound_statement
         {
		 fprintf(fasm, "# Restore registers\n");
		 fprintf(fasm, "\tpopq %%r15\n");
		 fprintf(fasm, "\tpopq %%r14\n");
		 fprintf(fasm, "\tpopq %%r13\n");
		 fprintf(fasm, "\tpopq %%r10\n");
		 fprintf(fasm, "\tpopq %%rbx\n");
                 fprintf(fasm, "\tpopq %%rbx\n");
                 fprintf(fasm, "\tleave\n");
		 fprintf(fasm, "\tret\n");
         }
	;

arg_list:
         arg
         | arg_list COMA arg
	 ;

arguments:
     arg_list
	 | /*empty*/
	 ;

arg: var_type WORD {
	local_vars_type[nargs] = current_type;
	local_vars_table[nlocals] = $2;
	fprintf(fasm, "\tmovq %%%s, -%d(%%rbp)\n", regArgs[nlocals], 8 * (nlocals + 1));
	nlocals++;
};

global_var: 
        var_type global_var_list SEMICOLON;

global_var_list: WORD {
	fprintf(fasm, "\t.data\n");
    fprintf(fasm, "\t.comm ");
    fprintf(fasm, "%s, 8\n", $1);

    global_vars_table[nglobals] = $<string_val>1;
    global_vars_type[nglobals] = current_type;
    nglobals++;
        }
| global_var_list COMA WORD {
	fprintf(fasm, "\t.comm ");
    fprintf(fasm, "%s, 8\n", $3);
    global_vars_table[nglobals] = $<string_val>3;
    global_vars_type[nglobals] = current_type; 
    nglobals++;
}
        ;

var_type: CHARSTAR {current_type = 1;} | CHARSTARSTAR {current_type = 0;} | LONG {current_type = 0;} | LONGSTAR {current_type = 0;} | VOID {current_type = 0;};

assignment:
         WORD EQUAL expression {
			char * id = $<string_val>1;
			int localvar = -1;
		  	for (int i = 0; i < nlocals; i++) {
				if (strcmp(id, local_vars_table[i]) == 0) {
					localvar = i;
					break;
				}
		  	}

			if (localvar != -1) {
				fprintf(fasm, "\tmovq %%%s, -%d(%%rbp)\n", regStk[top - 1], 8 * (localvar + 1));
			}
			else {
				fprintf(fasm, "\tmovq %%%s, %s\n", regStk[top - 1], id);
			}
			top--;
		 }
	 | WORD LBRACE expression RBRACE EQUAL expression {
		char *id = $<string_val>1;
    	int localvar = -1;
    	int is_char_ptr = 0;

    	for (int i = 0; i < nlocals; i++) {
        	if (strcmp(id, local_vars_table[i]) == 0) {
            	localvar = i;
            	is_char_ptr = (local_vars_type[i] == 1);
            	break;
        	}
    	}

    	if (localvar == -1) {
        	for (int i = 0; i < nglobals; i++) {
            	if (strcmp(id, global_vars_table[i]) == 0) {
                	is_char_ptr = (global_vars_type[i] == 1); 
                	break;
            	}
        	}
    	}

    	fprintf(fasm, "\tmovq %%%s, %%rax\n", regStk[top - 1]);  
    	fprintf(fasm, "\tmovq %%%s, %%rcx\n", regStk[top - 2]); 

    	if (is_char_ptr) {
        	if (localvar != -1) {
            	fprintf(fasm, "\tmovq -%d(%%rbp), %%rdx\n", 8 * (localvar + 1));
        	} else {
            	fprintf(fasm, "\tmovq %s, %%rdx\n", id);
        	}
        	fprintf(fasm, "\taddq %%rcx, %%rdx\n");
        	fprintf(fasm, "\tmovb %%al, (%%rdx)\n");   
    	} else {
        	fprintf(fasm, "\tleaq 0(,%%rcx,8), %%rcx\n");
        	if (localvar != -1) {
            	fprintf(fasm, "\tmovq -%d(%%rbp), %%rdx\n", 8 * (localvar + 1));
        	} else {
            	fprintf(fasm, "\tmovq %s, %%rdx\n", id);
        	}
        	fprintf(fasm, "\taddq %%rcx, %%rdx\n");
        	fprintf(fasm, "\tmovq %%rax, (%%rdx)\n");
    	}
    
    	top -= 2;
	 }
	 ;

call :
         WORD LPARENT  call_arguments RPARENT {
		 char * funcName = $<string_val>1;
		 int nargs = $<nargs>3;
		 int i;
		 fprintf(fasm,"     # func=%s nargs=%d\n", funcName, nargs);
     		 fprintf(fasm,"     # Move values from reg stack to reg args\n");
		 for (i=nargs-1; i>=0; i--) {
			top--;
			fprintf(fasm, "\tmovq %%%s, %%%s\n",
			  regStk[top], regArgs[i]);
		 }
		 if (!strcmp(funcName, "printf")) {
			 // printf has a variable number of arguments
			 // and it need the following
			 fprintf(fasm, "\tmovl    $0, %%eax\n");
		 }
		 fprintf(fasm, "\tcall %s\n", funcName);
		 fprintf(fasm, "\tmovq %%rax, %%%s\n", regStk[top]);
		 top++;
         }
      ;

call_arg_list:
         expression {
		$<nargs>$=1;
	 }
         | call_arg_list COMA expression {
		$<nargs>$++;
	 }

	 ;

call_arguments:
         call_arg_list { $<nargs>$=$<nargs>1; }
	 | /*empty*/ { $<nargs>$=0;}
	 ;

expression :
         logical_or_expr
	 ;

logical_or_expr:
         logical_and_expr
	 | logical_or_expr OROR logical_and_expr {
		fprintf(fasm, "\n\t# || \n");
		if (top<nregStk) {
			fprintf(fasm,"\torq %%%s, %%%s \n", regStk[top-1], regStk[top-2]);
			top--;
		}
	 }
	 ;

logical_and_expr:
         equality_expr
	 | logical_and_expr ANDAND equality_expr {
		fprintf(fasm, "\n\t# && \n");
		if (top<nregStk) {
			fprintf(fasm,"\tandq %%%s, %%%s \n", regStk[top-1], regStk[top-2]);
			top--;
		}
	 }
	 ;

equality_expr:
         relational_expr
	 | equality_expr EQUALEQUAL relational_expr {
		fprintf(fasm, "\n\t# == \n");
		if (top < nregStk) {
			fprintf(fasm, "\tcmp %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
			fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
			fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-1]);
			fprintf(fasm, "\tcmove %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
			top --;
		}
	 }
	 | equality_expr NOTEQUAL relational_expr {
		fprintf(fasm, "\n\t# != \n");
		if (top < nregStk) {
			fprintf(fasm, "\tcmp %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
			fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
			fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-1]);
			fprintf(fasm, "\tcmovne %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
			top --;
		}
	 }
	 ;

relational_expr:
         additive_expr
	 | relational_expr LESS additive_expr {
		fprintf(fasm, "\n\t# < \n");
		if (top < nregStk) {
			fprintf(fasm, "\tcmp %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
			fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
			fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-1]);
			fprintf(fasm, "\tcmovl %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
			top --;
		}
	 }
	 | relational_expr GREAT additive_expr {
		fprintf(fasm, "\n\t# > \n");
        if (top < nregStk) {
            fprintf(fasm, "\tcmp %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
            fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
            fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-1]);
            fprintf(fasm, "\tcmovg %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
            top--;
		}
	 }
	 | relational_expr LESSEQUAL additive_expr {
		fprintf(fasm, "\n\t# <= \n");
        if (top < nregStk) {
            fprintf(fasm, "\tcmp %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
            fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
            fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-1]);
            fprintf(fasm, "\tcmovle %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
            top--;
		}
	 }
	 | relational_expr GREATEQUAL additive_expr {
		fprintf(fasm, "\n\t# >= \n");
        if (top < nregStk) {
            fprintf(fasm, "\tcmp %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
            fprintf(fasm, "\tmovq $0, %%%s\n", regStk[top-2]);
            fprintf(fasm, "\tmovq $1, %%%s\n", regStk[top-1]);
            fprintf(fasm, "\tcmovge %%%s, %%%s\n", regStk[top-1], regStk[top-2]);
            top--;
		}
	 }
	 ;

additive_expr:
          multiplicative_expr
	  | additive_expr PLUS multiplicative_expr {
		fprintf(fasm,"\n\t# +\n");
		if (top<nregStk) {
			fprintf(fasm, "\taddq %%%s,%%%s\n", 
				regStk[top-1], regStk[top-2]);
			top--;
		}
	  }
	  | additive_expr MINUS multiplicative_expr {
		fprintf(fasm,"\n\t# +\n");
                if (top<nregStk) {
                        fprintf(fasm, "\tsubq %%%s,%%%s\n",
                                regStk[top-1], regStk[top-2]);
                        top--;
                }
	  }
	  ;

multiplicative_expr:
          primary_expr
	  | multiplicative_expr TIMES primary_expr {
		fprintf(fasm,"\n\t# *\n");
		if (top<nregStk) {
			fprintf(fasm, "\timulq %%%s,%%%s\n", 
				regStk[top-1], regStk[top-2]);
			top--;
		}
          }
	  | multiplicative_expr DIVIDE primary_expr {
		fprintf(fasm,"\n\t# *\n");
		if (top<nregStk) {
			fprintf(fasm, "\tmovq %%%s, %%rax\n", regStk[top-2]);
			fprintf(fasm, "\tcqto\n");
			fprintf(fasm, "\tidivq %%%s\n", regStk[top-1]);
			fprintf(fasm, "\tmovq %%rax, %%%s\n", regStk[top-2]);
			top--;
		}
	  }
	  | multiplicative_expr PERCENT primary_expr {
		fprintf(fasm,"\n\t# +\n");
        if (top<nregStk) {
			fprintf(fasm, "\tmovq %%%s, %%rax\n", regStk[top-2]);
            fprintf(fasm, "\tcqto\n");
            fprintf(fasm, "\tidivq %%%s\n", regStk[top-1]);
            fprintf(fasm, "\tmovq %%rdx, %%%s\n", regStk[top-2]);
            top--;
        }
	  }
	  ;

primary_expr:
	  STRING_CONST {
		  // Add string to string table.
		  // String table will be produced later
		  string_table[nstrings]=$<string_val>1;
		  fprintf(fasm, "\t#top=%d\n", top);
		  fprintf(fasm, "\n\t# push string %s top=%d\n",
			  $<string_val>1, top);
		  if (top<nregStk) {
		  	fprintf(fasm, "\tmovq $string%d, %%%s\n", 
				nstrings, regStk[top]);
			//fprintf(fasm, "\tmovq $%s,%%%s\n", 
				//$<string_val>1, regStk[top]);
			top++;
		  }
		  nstrings++;
	  }
          | call {
			fprintf(fasm, "\tmovq %%rax, %%%s\n", regStk[top - 1]);
		  }
	  | WORD {
		  char * id = $<string_val>1;
		  int localvar = -1;
		  for (int i = 0; i < nlocals; i++) {
			if (strcmp(id, local_vars_table[i]) == 0) {
				localvar = i;
				break;
			}
		  }

		  if (localvar != -1) {
			fprintf(fasm, "\tmovq -%d(%%rbp),%%%s\n", 8 * (localvar + 1), regStk[top]);
		  }
		  else {
			fprintf(fasm, "\tmovq %s,%%%s\n", id, regStk[top]);
		  }

		  top++;
	  }
	  | WORD LBRACE expression RBRACE {
        char * id = $<string_val>1;
    	int localvar = -1;
    	int is_char_ptr = 0;

    	for (int i = 0; i < nlocals; i++) {
        	if (strcmp(id, local_vars_table[i]) == 0) {
            	localvar = i;
            	is_char_ptr = (local_vars_type[i] == 1); 
            	break;
        	}
    	}

    	if (localvar == -1) {
        	for (int i = 0; i < nglobals; i++) {
            	if (strcmp(id, global_vars_table[i]) == 0) {
                	is_char_ptr = (global_vars_type[i] == 1); 
                	break;
            	}
        	}
    	}

    	if (is_char_ptr) {
        	if (localvar != -1) {
            	fprintf(fasm, "\tmovq -%d(%%rbp), %%rdx\n", 8 * (localvar + 1));
        	} else {
            	fprintf(fasm, "\tmovq %s, %%rdx\n", id);
        	}
        	fprintf(fasm, "\taddq %%%s, %%rdx\n", regStk[top - 1]);
        	fprintf(fasm, "\tmovzbq (%%rdx), %%%s\n", regStk[top - 1]);
    	} else {
        	fprintf(fasm, "\tmovq %%%s, %%rcx\n", regStk[top - 1]);
        	fprintf(fasm, "\tleaq 0(,%%rcx,8), %%rcx\n");
        
        	if (localvar != -1) {
            	fprintf(fasm, "\tmovq -%d(%%rbp), %%rdx\n", 8 * (localvar + 1));
        	} else {
            	fprintf(fasm, "\tmovq %s, %%rdx\n", id);
        	}
        	fprintf(fasm, "\taddq %%rcx, %%rdx\n");
        	fprintf(fasm, "\tmovq (%%rdx), %%%s\n", regStk[top - 1]);
    	}
	  }
	  | AMPERSAND WORD {
		char *id = $<string_val>2;
		int localvar = -1;
		for (int i = 0; i < nlocals; i++) {
			if (strcmp(id, local_vars_table[i]) == 0) {
				localvar = i;
				break;
			}
		}

		if (localvar != -1) {
			fprintf(fasm, "\tleaq -%d(%%rbp), %%%s\n", 8 * (localvar + 1), regStk[top]);
		}
		else {
			fprintf(fasm, "\tleaq %s(%%rip), %%%s\n", id, regStk[top]);
		}

		top++;
	  }
	  | INTEGER_CONST {
		  fprintf(fasm, "\n\t# push %s\n", $<string_val>1);
		  if (top<nregStk) {
			fprintf(fasm, "\tmovq $%s,%%%s\n", 
				$<string_val>1, regStk[top]);
			top++;
		  }
	  }
	  | LPARENT expression RPARENT
	  ;

compound_statement:
	 LCURLY statement_list RCURLY
	 ;

statement_list:
         statement_list statement
	 | /*empty*/
	 ;

local_var:
        {current_type = 0;}var_type local_var_list SEMICOLON;

local_var_list: 
			WORD {
				assert(nlocals < MAX_LOCALS);
				local_vars_table[nlocals] = $<string_val>1;
				local_vars_type[nlocals] = current_type;
				nlocals++;
			} 
        | local_var_list COMA WORD {
			assert(nlocals < MAX_LOCALS);
			local_vars_table[nlocals] = $<string_val>3;
			local_vars_type[nlocals] = current_type;
			nlocals++;
		}
        ;

statement:
         assignment SEMICOLON
	 | call SEMICOLON { top= 0; /* Reset register stack */ }
	 | local_var
	 | compound_statement
	 | IF LPARENT expression RPARENT {
		$<my_nlabel>1 = nlabel;
        nlabel++;

        fprintf(fasm, "\tcmpq $0, %%%s\n", regStk[top - 1]);
        fprintf(fasm, "\tje if_else_%d\n", $<my_nlabel>1);
        top--;
    } statement {
        fprintf(fasm, "\tjmp if_end_%d\n", $<my_nlabel>1);
        fprintf(fasm, "if_else_%d:\n", $<my_nlabel>1);
    } else_optional {
        fprintf(fasm, "if_end_%d:\n", $<my_nlabel>1);
    }
	 | WHILE LPARENT {
		$<my_nlabel>1 = nlabel;
		loop_labels[loop_depth] = $<my_nlabel>1;
		continue_labels[loop_depth] = $<my_nlabel>1;
		loop_depth++;

		fprintf(fasm, "continue_%d:\n", $<my_nlabel>1);
		fprintf(fasm, "while_start_%d:\n", $<my_nlabel>1);
	 } expression RPARENT {
		fprintf(fasm, "\tcmpq $0, %%%s\n", regStk[top - 1]);
		fprintf(fasm, "\tje while_end_%d\n", $<my_nlabel>1);
		top--;
	 } statement {
		fprintf(fasm, "\tjmp continue_%d\n", $<my_nlabel>1);
		fprintf(fasm, "while_end_%d:\n", $<my_nlabel>1);
		loop_depth--;
	 }
	 | DO {
		$<my_nlabel>1 = nlabel++;
		loop_labels[loop_depth] = $<my_nlabel>1;
		continue_labels[loop_depth] = $<my_nlabel>1;
		loop_depth++;
		fprintf(fasm, "while_start_%d:\n", $<my_nlabel>1);
	 } statement WHILE LPARENT expression RPARENT SEMICOLON {
		fprintf(fasm, "continue_%d:\n", $<my_nlabel>1);
		fprintf(fasm, "\tcmpq $0, %%%s\n", regStk[top - 1]);
		fprintf(fasm, "\tjne while_start_%d\n", $<my_nlabel>1);
		fprintf(fasm, "while_end_%d:\n", $<my_nlabel>1);
		top--;
		loop_depth--;
	 }
	 | FOR LPARENT assignment SEMICOLON {
		$<my_nlabel>1 = nlabel++;
		loop_labels[loop_depth] = $<my_nlabel>1;
		continue_labels[loop_depth] = $<my_nlabel>1;
		loop_depth++;
		fprintf(fasm, "while_start_%d:\n", $<my_nlabel>1);
	 } expression SEMICOLON {
		fprintf(fasm, "\tcmpq $0, %%%s\n", regStk[top - 1]);
		fprintf(fasm, "\tje while_end_%d\n", $<my_nlabel>1);
		top--;
		$<my_nlabel>2 = nlabel++;
		fprintf(fasm, "\tjmp while_body_%d\n", $<my_nlabel>2);
		fprintf(fasm, "continue_%d:\n", $<my_nlabel>1);
	 } assignment RPARENT {
		fprintf(fasm, "\tjmp while_start_%d\n", $<my_nlabel>1);
		fprintf(fasm, "while_body_%d:\n", $<my_nlabel>2);
	 } statement {
		fprintf(fasm, "\tjmp continue_%d\n", $<my_nlabel>1);
		fprintf(fasm, "while_end_%d:\n", $<my_nlabel>1);
		loop_depth--;
	 }
	 | jump_statement
	 ;

else_optional:
         ELSE  statement
	 | /* empty */
         ;

jump_statement:
     CONTINUE SEMICOLON {
		if (loop_depth > 0) {
			int current_loop = continue_labels[loop_depth - 1];
			fprintf(fasm, "\tjmp continue_%d\n", current_loop);
		}
	 }
	 | BREAK SEMICOLON {
		if (loop_depth > 0) {
			int current_loop = continue_labels[loop_depth - 1];
			fprintf(fasm, "\tjmp while_end_%d\n", current_loop);
		}
	 }
	 | RETURN expression SEMICOLON {
		 fprintf(fasm, "\tmovq %%%s, %%rax\n", regStk[top-1]);
		 fprintf(fasm, "\tpopq %%r15\n");
    	fprintf(fasm, "\tpopq %%r14\n");
    	fprintf(fasm, "\tpopq %%r13\n");
    	fprintf(fasm, "\tpopq %%r10\n");
    	fprintf(fasm, "\tpopq %%rbx\n");
    	fprintf(fasm, "\tpopq %%rbx\n");
    	fprintf(fasm, "\tleave\n");
    	fprintf(fasm, "\tret\n");
    	top = 0;
	 }
	 ;

%%

void yyset_in (FILE *  in_str );

int
yyerror(const char * s)
{
	fprintf(stderr,"%s:%d: %s\n", input_file, line_number, s);
}


int
main(int argc, char **argv)
{
	printf("-------------WARNING: You need to implement global and local vars ------\n");
	printf("------------- or you may get problems with top------\n");
	
	// Make sure there are enough arguments
	if (argc <2) {
		fprintf(stderr, "Usage: simple file\n");
		exit(1);
	}

	// Get file name
	input_file = strdup(argv[1]);

	int len = strlen(input_file);
	if (len < 2 || input_file[len-2]!='.' || input_file[len-1]!='c') {
		fprintf(stderr, "Error: file extension is not .c\n");
		exit(1);
	}

	// Get assembly file name
	asm_file = strdup(input_file);
	asm_file[len-1]='s';

	// Open file to compile
	FILE * f = fopen(input_file, "r");
	if (f==NULL) {
		fprintf(stderr, "Cannot open file %s\n", input_file);
		perror("fopen");
		exit(1);
	}

	// Create assembly file
	fasm = fopen(asm_file, "w");
	if (fasm==NULL) {
		fprintf(stderr, "Cannot open file %s\n", asm_file);
		perror("fopen");
		exit(1);
	}

	// Uncomment for debugging
	//fasm = stderr;

	// Create compilation file
	// 
	yyset_in(f);
	yyparse();

	// Generate string table
	int i;
	for (i = 0; i<nstrings; i++) {
		fprintf(fasm, "string%d:\n", i);
		fprintf(fasm, "\t.string %s\n\n", string_table[i]);
	}

	fclose(f);
	fclose(fasm);

	return 0;
}


