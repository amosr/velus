# ********************************************************************#
#                                                                     #
#                 The Vélus verified Lustre compiler                  #
#                                                                     #
#             (c) 2019 Inria Paris (see the AUTHORS file)             #
#                                                                     #
#  Copyright Institut National de Recherche en Informatique et en     #
#  Automatique. All rights reserved. This file is distributed under   #
#  the terms of the INRIA Non-Commercial License Agreement (see the   #
#  LICENSE file).                                                     #
#                                                                     #
# ********************************************************************#

#
# invoke make with 'VERBOSE=1' to verbose the output
#

include variables.mk

.PHONY: all clean compcert parser proof extraction $(VELUS) $(EXAMPLESDIR) runtests runexamples

all: $(VELUS)

# COMPCERT COQ
compcert: $(COMPCERTDIR)/Makefile.config
	@echo "${bold}Building CompCert...${normal}"
	$(MAKE) $(COMPCERTFLAGS) #compcert.ini driver/Version.ml proof
	@echo "${bold}OK.${normal}"

# LUSTRE PARSER
parser:
	@echo "${bold}Building Lustre parser...${normal}"
	$(MAKE) $(PARSERFLAGS) all
	@echo "${bold}OK.${normal}"

# VELUS COQ
proof: compcert parser $(MAKEFILEAUTO) $(MAKEFILECONFIG)
	@echo "${bold}Building Velus proof...${normal}"
	$(MAKE) -s -f $(MAKEFILEAUTO) check-admitted
	test -f .depend || $(MAKE) -s -f $(MAKEFILEAUTO) depend
	$(MAKE) -s -f $(MAKEFILEAUTO) all
	@echo "${bold}OK.${normal}"

$(MAKEFILEAUTO): $(AUTOMAKE) $(COQPROJECT)
	./$< -e ./$(EXTRACTION)/Extraction.v -f $(EXTRACTED) -o $@ $(COQPROJECT)

# EXTRACTION
extraction: proof
	@echo "${bold}Extracting Velus Ocaml code...${normal}"
	$(MAKE) -s -f $(MAKEFILEAUTO) $@
	cp -f $(PARSERDIR)/LustreLexer.ml\
		$(PARSERDIR)/Relexer.ml\
		$(PARSERDIR)/LustreParser2.ml\
		$(PARSERDIR)/LustreParser2.mli\
		$(SRC_DIR)/CoreExpr/coreexprlib.ml\
		$(SRC_DIR)/NLustre/nlustrelib.ml\
		$(SRC_DIR)/Stc/stclib.ml\
		$(SRC_DIR)/Obc/obclib.ml\
		$(SRC_DIR)/ObcToClight/interfacelib.ml\
		$(COMPCERT_INCLUDES:%=$(COMPCERTDIR)/%/*.ml*)\
		$(EXTRACTED)
	@echo "${bold}OK.${normal}"

# VELUS
$(VELUS): extraction $(SRC_DIR)/$(VELUSMAIN).ml $(SRC_DIR)/veluslib.ml
	@echo "${bold}Building Velus...${normal}"
	ocamlbuild $(FLAGS) $(VELUSMAIN).$(TARGET)
	mv $(VELUSMAIN).$(TARGET) $@
	cp $(COMPCERTDIR)/compcert.ini $(BUILDDIR)/$(SRC_DIR)/compcert.ini
	@echo "${bold}Done.${normal}"

# TOOLS
$(AUTOMAKE): $(TOOLSDIR)/$(AUTOMAKE).ml
	ocamlopt -o $@ str.cmxa $<

$(TOOLSDIR)/$(AUTOMAKE).ml: $(TOOLSDIR)/$(AUTOMAKE).mll
	@echo "${bold}Building $(AUTOMAKE) tool...${normal}"
	ocamllex $<

# EXAMPLES
# $(EXAMPLESDIR): $(VELUS)
# 	$(MAKE) $(EXAMPLESFLAGS)

runexamples: $(VELUS)
	VELUS=$(MKFILE_DIR)/$(VELUS) $(RUNEXAMPLES)

runtests: $(VELUS)
	VELUS=$(MKFILE_DIR)/$(VELUS) $(RUNTESTS)

# CLEAN
clean:
	if [ -f $(MAKEFILEAUTO) ] ; then $(MAKE) -s -f $(MAKEFILEAUTO) $@; fi;
	rm -f $(MAKEFILEAUTO)
	rm -f $(AUTOMAKE) $(TOOLSDIR)/$(AUTOMAKE).ml $(TOOLSDIR)/$(AUTOMAKE).cm* $(TOOLSDIR)/$(AUTOMAKE).o
	$(MAKE) $(PARSERFLAGS) $@
	# $(MAKE) $(EXAMPLESFLAGS) $@
	ocamlbuild -clean

realclean: clean
	rm -f $(MAKEFILECONFIG) $(COQPROJECT)
	$(MAKE) $(COMPCERTFLAGS) $<
	# $(MAKE) $(EXAMPLESFLAGS) $@
