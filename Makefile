# Created by Stuart, vero (and its preferred cat) on October 5 2025.

define HELP_MESSAGE
	STEP Document Build System (metanorma >= 2.3.1)

	Prerequisites: ruby, bundler, python3, fontist, eengine, git
	               docker (optional, for container builds)

	Build targets (append 'docker' for Docker mode, e.g. make srl docker):
	  make <part>          Build a single part, e.g. make event, make 10303-47
	  make single-pattern '<glob>'
	                       Build matching documents as a collection
	                       e.g. make single-pattern 'activity*'
	  make srl             Build Schema Reference Library (SRL)
	  make smrl            Build Schema Model Reference Library (SMRL)

	Feature build targets:
	  make remote_feature ROOT=<module>   Build module + dependencies (from HEAD)
	  make local_feature ROOT=<module>    Build with uncommitted changes
	  make rebuild-feature                Full rebuild of last feature build
	  make rebuild-feature-quick          Quick rebuild (text changes only)
	  make diff-feature                   Show changes since last feature build
	  make diff_collection                Build only documents that differ from develop
	    Options: BRANCH=<branch> REF=<base>

	Setup targets:
	  make update          Update gems (bundle update + fontist update)
	  make update docker   Rebuild the Docker image

	Options:
	  POSTPROCESS=smrl     Convert feature build output to SMRL format

	  make help            Show this text
endef
export HELP_MESSAGE

DIRS := $(shell  find documents -maxdepth 1 -type d ! -path '*/.*' -exec basename {} \; )

UNAME_S := $(shell uname -s)
DO_MAKE-SINGLE-SHELL :=
DO_MAKE-SINGLE-POWERSHELL :=
ifeq ($(UNAME_S),Linux)
    OS_NAME := linux
	DO_MAKE-SINGLE-SHELL := yes
endif
ifeq ($(UNAME_S),Darwin)
    OS_NAME := macos
	DO_MAKE-SINGLE-SHELL := yes
endif
ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
    OS_NAME := windows
	DO_MAKE-SINGLE-POWERSHELL := yes
endif
ifeq ($(findstring MSYS,$(UNAME_S)),MSYS)
    OS_NAME := windows
	DO_MAKE-SINGLE-POWERSHELL := yes
endif

# Python: use venv if available, otherwise system python
VENV_DIR ?= $(HOME)/venvs/wg12-step
ifeq ($(OS_NAME),windows)
    PYTHON := python
else
    ifneq ($(wildcard $(VENV_DIR)/bin/python3),)
        PYTHON := $(VENV_DIR)/bin/python3
    else
        PYTHON := python3
    endif
endif

# Extract pattern argument for single-pattern target
# Strip quotes to handle both bash (removes quotes) and PowerShell (keeps quotes) callers
ifneq ($(filter single-pattern,$(MAKECMDGOALS)),)
PATTERN_ARG_RAW := $(word 2,$(MAKECMDGOALS))
PATTERN_ARG := $(subst ',,$(PATTERN_ARG_RAW))
ifneq ($(PATTERN_ARG),)
# Create no-op rule for the pattern argument to prevent "no rule" error
$(PATTERN_ARG_RAW):
	@:
endif
endif

help:
	@echo "$$HELP_MESSAGE"

all:
	@echo "This is $(OS_NAME)"

.PHONY: docker other single single-pattern remote_feature local_feature _run-feature rebuild-feature rebuild-feature-quick diff_collection smrl_feature

# Post-processing mode: "rename" (default) or "smrl" (full SMRL conversion)
POSTPROCESS ?= rename
single: $(DIRS)

update:
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "docker target detected, update"
		docker build -t suma:latest .
else
	@echo "cross-platform update"
		bundle update
		fontist update
endif

10303-%:
	@echo "make only part $@"
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	$(MAKE) iso-$@ docker
else
	$(MAKE) iso-$@
endif

$(DIRS): %:
	@echo "make single $@"
	# #procuding metanorma-single artifacts
ifeq ($(DO_MAKE-SINGLE-SHELL),yes)
	$(MAKE) MAKE-SINGLE-SHELL ID=$@
endif
ifeq ($(DO_MAKE-SINGLE-POWERSHELL),yes)
	$(MAKE) MAKE-SINGLE-POWERSHELL ID=$@
endif
#suma build
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	time docker run -it -v '${CURDIR}:/metanorma' suma:latest suma build metanorma-single.yml 2>&1 | tee metanorma-single-log.txt
else
	@echo "macOS detected"
	time bundle exec suma build metanorma-single.yml 2>&1 | tee metanorma-single-log.txt
endif
endif

ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	time bundle exec suma build metanorma-single.yml 2>&1 | tee metanorma-single-log.txt
endif

ifeq ($(OS_NAME),windows)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "windows + docker target detected"
	time docker run -it -v '${CURDIR}:/metanorma' suma:latest suma build metanorma-single.yml 2>&1 | tee metanorma-single-log.txt
else
	@echo "windows detected"
	time bundle exec suma build metanorma-single.yml 2>&1 | tee metanorma-single-log.txt
endif
endif
	@echo ""
	@echo "Post-processing index.html..."
	@$(PYTHON) $(CURDIR)/scripts/rename_feature_docs.py $(CURDIR)/_site
	@echo ""
	@echo "Single build complete! Output in: _site/"

single-pattern:
ifeq ($(PATTERN_ARG),)
	$(error Usage: make single-pattern '<pattern>' (e.g., make single-pattern 'activity*'))
endif
ifeq ($(DO_MAKE-SINGLE-SHELL),yes)
	@pattern="$(PATTERN_ARG)"; \
	matches=$$(ls -d documents/$$pattern 2>/dev/null | xargs -n1 basename 2>/dev/null); \
	if [ -z "$$matches" ]; then \
		echo "No directories found matching pattern: $$pattern"; \
		exit 1; \
	fi; \
	count=$$(echo "$$matches" | wc -l | tr -d ' '); \
	echo "Found $$count matching directories:"; \
	echo "$$matches"; \
	echo ""; \
	echo "Generating collection-pattern.yml..."; \
	echo "---" > collection-pattern.yml; \
	echo "directives:" >> collection-pattern.yml; \
	echo "  - documents-inline" >> collection-pattern.yml; \
	echo "bibdata:" >> collection-pattern.yml; \
	echo "  title:" >> collection-pattern.yml; \
	echo "    - language: en" >> collection-pattern.yml; \
	echo "      content: \"ISO 10303 STEP Pattern Build: $$pattern\"" >> collection-pattern.yml; \
	echo "  type: collection" >> collection-pattern.yml; \
	echo "  docid:" >> collection-pattern.yml; \
	echo "    type: iso" >> collection-pattern.yml; \
	echo "    id: pattern-$$pattern" >> collection-pattern.yml; \
	echo "format:" >> collection-pattern.yml; \
	echo "  - html" >> collection-pattern.yml; \
	echo "manifest:" >> collection-pattern.yml; \
	echo "  level: collection" >> collection-pattern.yml; \
	echo "  title: \"Pattern Collection: $$pattern\"" >> collection-pattern.yml; \
	echo "  docref:" >> collection-pattern.yml; \
	for dir in $$matches; do \
		if [ -f "documents/$$dir/collection.yml" ]; then \
			echo "    - file: documents/$$dir/collection.yml" >> collection-pattern.yml; \
		else \
			echo "Warning: documents/$$dir/collection.yml not found, skipping"; \
		fi; \
	done; \
	echo "Generating metanorma-pattern.yml..."; \
	echo "---" > metanorma-pattern.yml; \
	echo "metanorma:" >> metanorma-pattern.yml; \
	echo "  source:" >> metanorma-pattern.yml; \
	echo "    files:" >> metanorma-pattern.yml; \
	echo "      - collection-pattern.yml" >> metanorma-pattern.yml; \
	echo "" >> metanorma-pattern.yml; \
	echo "    collection:" >> metanorma-pattern.yml; \
	echo "      organization: \"ISO/TC 184/SC 4/WG 12\"" >> metanorma-pattern.yml; \
	echo "      name: \"ISO 10303 STEP Pattern: $$pattern\"" >> metanorma-pattern.yml; \
	echo "Collection files generated."
endif
ifeq ($(DO_MAKE-SINGLE-POWERSHELL),yes)
	powershell -ExecutionPolicy Bypass -File scripts/single-pattern-build.ps1 -Pattern $(PATTERN_ARG)
endif
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	time docker run -it -v '${CURDIR}:/metanorma' suma:latest suma build metanorma-pattern.yml 2>&1 | tee metanorma-pattern-log.txt
else
	@echo "macOS detected"
	time bundle exec suma build metanorma-pattern.yml 2>&1 | tee metanorma-pattern-log.txt
endif
endif
ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	time bundle exec suma build metanorma-pattern.yml 2>&1 | tee metanorma-pattern-log.txt
endif
ifeq ($(OS_NAME),windows)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "windows + docker target detected"
	time docker run -it -v '${CURDIR}:/metanorma' suma:latest suma build metanorma-pattern.yml 2>&1 | tee metanorma-pattern-log.txt
else
	@echo "windows detected"
	time bundle exec suma build metanorma-pattern.yml 2>&1 | tee metanorma-pattern-log.txt
endif
endif
	@echo ""
	@echo "Post-processing index.html..."
	@$(PYTHON) $(CURDIR)/scripts/rename_feature_docs.py $(CURDIR)/_site
	@echo ""
	@echo "Pattern build complete! Output in: _site/"

SRL_WORKTREE_BASE ?= $(HOME)/work
SRL_WORKTREE = $(SRL_WORKTREE_BASE)/wg12-step-build-srl

srl:
	@echo "make srl"
	@echo "Creating worktree at $(SRL_WORKTREE)..."
	@git worktree remove --force $(SRL_WORKTREE) 2>/dev/null || true
	@git worktree add --detach $(SRL_WORKTREE) develop
	@echo "Copying uncommitted changes to worktree..."
	@git diff --name-only | while read f; do cp "$$f" "$(SRL_WORKTREE)/$$f"; done
	@echo "Worktree ready: $(SRL_WORKTREE)"
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	cd $(SRL_WORKTREE) && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-srl.yml 2>&1 | tee metanorma-srl-log.txt
else
	@echo "macOS detected"
	cd $(SRL_WORKTREE) && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-srl.yml 2>&1 | tee metanorma-srl-log.txt
endif
endif
ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	cd $(SRL_WORKTREE) && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-srl.yml 2>&1 | tee metanorma-srl-log.txt
endif
ifeq ($(OS_NAME),windows)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "windows + docker target detected"
	cd $(SRL_WORKTREE) && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-srl.yml 2>&1 | tee metanorma-srl-log.txt
else
	@echo "windows detected"
	cd $(SRL_WORKTREE) && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-srl.yml 2>&1 | tee metanorma-srl-log.txt
endif
endif
	@echo ""
	@echo "Post-processing: Converting to SMRL format..."
	@./scripts/suma2smrl.sh $(SRL_WORKTREE) --publish --ci-repo $(CURDIR)/../wg12-ci
	@echo ""
	@echo "SRL build complete!"
	@echo "  Site: $(SRL_WORKTREE)/index.html"
	@echo "  open $(SRL_WORKTREE)/index.html"

smrl:
	@echo "make smrl"
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	time docker run -it -v '${CURDIR}:/metanorma' suma:latest suma build metanorma-smrl-all.yml 2>&1 | tee metanorma-smrl-all-log.txt
else
	@echo "macOS detected"
	time bundle exec suma build metanorma-smrl-all.yml 2>&1 | tee metanorma-smrl-all-log.txt
endif
endif

ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	time bundle exec suma build metanorma-smrl-all.yml 2>&1 | tee metanorma-smrl-all-log.txt
endif

ifeq ($(OS_NAME),windows)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "windows + docker target detected"
	time docker run -it -v '${CURDIR}:/metanorma' suma:latest suma build metanorma-smrl-all.yml 2>&1 | tee metanorma-smrl-all-log.txt
else
	@echo "windows detected"
	time bundle exec suma build metanorma-smrl-all.yml 2>&1 | tee metanorma-smrl-all-log.txt
endif
endif

# Optional docker target (so make doesn't complain)
docker:
	@true


MAKE-SINGLE-SHELL:
	@echo "producing metarnorma single artefact for shell for $(ID)"
	echo "---" > metanorma-single.yml
	echo "metanorma:" >> metanorma-single.yml
	echo "  source:" >> metanorma-single.yml
	echo "    files:" >> metanorma-single.yml
	echo "      - collection-single.yml" >> metanorma-single.yml
	echo "" >> metanorma-single.yml
	echo "    collection:" >> metanorma-single.yml
	echo '      organization: "ISO/TC 184/SC 4/WG 12"' >> metanorma-single.yml
	echo '      name: "ISO 10303 STEP Single Part"' >> metanorma-single.yml
	awk 'NR==1,/from:/' documents/$(ID)/collection.yml > collection-single.yml
	echo "format:" >> collection-single.yml
	echo "  - html" >> collection-single.yml
	echo "manifest:" >> collection-single.yml
	echo "  level: collection" >> collection-single.yml
	echo "  title: ISO Collection" >> collection-single.yml
	echo "  docref:" >> collection-single.yml
	echo "      - file: documents/$(ID)/collection.yml" >> collection-single.yml


MAKE-SINGLE-POWERSHELL:
	@echo "producing metarnorma single artefact for windows for $(ID)"
	$(file > metanorma-single.yml,---)
	$(file >> metanorma-single.yml,metanorma:)
	$(file >> metanorma-single.yml,  source:)
	$(file >> metanorma-single.yml,    files:)
	$(file >> metanorma-single.yml,      - collection-single.yml)
	$(file >> metanorma-single.yml)
	$(file >> metanorma-single.yml,    collection:)
	$(file >> metanorma-single.yml,      organization: "ISO/TC 184/SC 4/WG 12")
	$(file >> metanorma-single.yml,      name: "ISO 10303 STEP Single Part")
	$(shell  awk 'NR==1,/from:/' documents/$(ID)/collection.yml > collection-single.yml)
	$(file >> collection-single.yml,format:)
	$(file >> collection-single.yml,  - html)
	$(file >> collection-single.yml,manifest:)
	$(file >> collection-single.yml,  level: collection)
	$(file >> collection-single.yml,  title: ISO Collection)
	$(file >> collection-single.yml,  docref:)
	$(file >> collection-single.yml,      - file: documents/$(ID)/collection.yml)


# Feature Build Targets
# Build a feature (module + all dependencies) using eengine --shtolo
# remote_feature: builds from committed branch state only (worktree from HEAD)
# local_feature:  builds from committed + uncommitted changes (copies dirty files into worktree)
# Usage: make remote_feature ROOT=<module_name>
#        make local_feature ROOT=<module_name>
#        make remote_feature ROOT=<module_name> docker
#        BUILD_BASE=/custom/path make remote_feature ROOT=<module_name>

remote_feature: _run-feature

local_feature: FEATURE_MODE = local
local_feature: _run-feature

_run-feature:
ifndef ROOT
	$(error ROOT is required. Usage: make remote_feature ROOT=<module_name>)
endif
	@echo "Building feature for module: $(ROOT) (mode: $(FEATURE_MODE))"
ifeq ($(DO_MAKE-SINGLE-SHELL),yes)
	./scripts/feature-build.sh $(ROOT) $(if $(filter local,$(FEATURE_MODE)),--local)
endif
ifeq ($(DO_MAKE-SINGLE-POWERSHELL),yes)
	powershell -ExecutionPolicy Bypass -File scripts/feature-build.ps1 -RootModule $(ROOT)
endif
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	cd "$$(cat .feature-build-worktree)" && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
else
	@echo "macOS detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
endif
ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
ifeq ($(OS_NAME),windows)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "windows + docker target detected"
	cd "$$(cat .feature-build-worktree)" && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
else
	@echo "windows detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
endif
	@# Copy dependency graph to _site if it exists
	@if [ -f "$$(cat .feature-build-worktree)/$(ROOT)_dependencies.svg" ]; then \
		cp "$$(cat .feature-build-worktree)/$(ROOT)_dependencies.svg" "$$(cat .feature-build-worktree)/_site/"; \
	fi
	@# Post-process based on POSTPROCESS mode
ifeq ($(POSTPROCESS),smrl)
	@echo "Post-processing: Converting to SMRL format..."
	@./scripts/suma2smrl.sh "$$(cat .feature-build-worktree)" --publish --ci-repo $(CURDIR)/../wg12-ci
else
	@echo "Post-processing: Renaming documents to ISO format..."
	@$(PYTHON) $(CURDIR)/scripts/rename_feature_docs.py "$$(cat .feature-build-worktree)/_site" --repo-root $(CURDIR) --root-module $$(cat .feature-build-module)
endif
	@echo ""
	@echo "Feature build complete!"
	@echo ""
	@echo "Output files:"
ifeq ($(POSTPROCESS),smrl)
	@echo "  Site: $$(cat .feature-build-worktree)/index.html"
else
	@echo "  Documents: $$(cat .feature-build-worktree)/_site/index.html"
endif
	@if [ -f "$$(cat .feature-build-worktree)/_site/$(ROOT)_dependencies.svg" ]; then \
		echo "  Dependency graph: $$(cat .feature-build-worktree)/_site/$(ROOT)_dependencies.svg"; \
	fi
	@echo ""
	@echo "To open in browser:"
ifeq ($(POSTPROCESS),smrl)
	@echo "  open $$(cat .feature-build-worktree)/index.html"
else
	@echo "  open $$(cat .feature-build-worktree)/_site/index.html"
endif
	@if [ -f "$$(cat .feature-build-worktree)/_site/$(ROOT)_dependencies.svg" ]; then \
		echo "  open $$(cat .feature-build-worktree)/_site/$(ROOT)_dependencies.svg"; \
	fi

# Show changes since last feature build
diff-feature:
	@if [ ! -f .feature-build-commit ]; then \
		echo "Error: No previous feature build found. Run 'make remote_feature ROOT=<module>' or 'make local_feature ROOT=<module>' first."; \
		exit 1; \
	fi
	@echo "=== Changes since last feature build ==="
	@echo "Previous build commit: $$(cat .feature-build-commit)"
	@echo "Current HEAD: $$(git rev-parse HEAD)"
	@echo ""
	@echo "=== Commits since last build ==="
	@git log --oneline $$(cat .feature-build-commit)..HEAD -- documents/ schemas/
	@echo ""
	@echo "=== Files changed ==="
	@git diff --stat $$(cat .feature-build-commit)..HEAD -- documents/ schemas/

# Full rebuild: show changes, re-run eengine, recreate worktree
rebuild-feature:
	@if [ ! -f .feature-build-module ]; then \
		echo "Error: No previous feature build found. Run 'make remote_feature ROOT=<module>' or 'make local_feature ROOT=<module>' first."; \
		exit 1; \
	fi
	@PREV_COMMIT=$$(cat .feature-build-commit 2>/dev/null || echo "unknown"); \
	ROOT=$$(cat .feature-build-module); \
	echo "=== Rebuilding feature for module: $$ROOT ==="; \
	echo "Previous build: $$PREV_COMMIT"; \
	echo "Current HEAD: $$(git rev-parse HEAD)"; \
	if [ "$$PREV_COMMIT" != "unknown" ] && [ "$$PREV_COMMIT" != "$$(git rev-parse HEAD)" ]; then \
		echo ""; \
		echo "=== Changes since last build ==="; \
		git log --oneline $$PREV_COMMIT..HEAD -- documents/ schemas/ || true; \
		echo ""; \
	fi
	@echo "Running full feature build..."
ifeq ($(DO_MAKE-SINGLE-SHELL),yes)
	./scripts/feature-build.sh $$(cat .feature-build-module)
endif
ifeq ($(DO_MAKE-SINGLE-POWERSHELL),yes)
	powershell -ExecutionPolicy Bypass -File scripts/feature-build.ps1 -RootModule $$(cat .feature-build-module)
endif
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	cd "$$(cat .feature-build-worktree)" && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
else
	@echo "macOS detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
endif
ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
ifeq ($(OS_NAME),windows)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "windows + docker target detected"
	cd "$$(cat .feature-build-worktree)" && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
else
	@echo "windows detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
endif
	@# Post-process based on POSTPROCESS mode
ifeq ($(POSTPROCESS),smrl)
	@echo "Post-processing: Converting to SMRL format..."
	@./scripts/suma2smrl.sh "$$(cat .feature-build-worktree)" --publish --ci-repo $(CURDIR)/../wg12-ci
else
	@echo "Post-processing: Renaming documents to ISO format..."
	@$(PYTHON) $(CURDIR)/scripts/rename_feature_docs.py "$$(cat .feature-build-worktree)/_site" --repo-root $(CURDIR) --root-module $$(cat .feature-build-module)
endif
	@echo ""
	@echo "Feature rebuild complete! Output in: $$(cat .feature-build-worktree)/_site"

# Quick rebuild: reuse existing worktree and collection (text changes only)
rebuild-feature-quick:
	@if [ ! -f .feature-build-worktree ]; then \
		echo "Error: No previous feature build found. Run 'make remote_feature ROOT=<module>' or 'make local_feature ROOT=<module>' first."; \
		exit 1; \
	fi
	@echo "Quick rebuild in worktree: $$(cat .feature-build-worktree)"
	@echo "NOTE: This reuses existing collection - schema dependency changes will not be detected."
	@echo "      Use 'make rebuild-feature' for a full rebuild with eengine."
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	cd "$$(cat .feature-build-worktree)" && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
else
	@echo "macOS detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
endif
ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
ifeq ($(OS_NAME),windows)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "windows + docker target detected"
	cd "$$(cat .feature-build-worktree)" && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
else
	@echo "windows detected"
	cd "$$(cat .feature-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-feature.yml 2>&1 | tee metanorma-feature-log.txt
endif
endif
	@# Post-process based on POSTPROCESS mode
ifeq ($(POSTPROCESS),smrl)
	@echo "Post-processing: Converting to SMRL format..."
	@./scripts/suma2smrl.sh "$$(cat .feature-build-worktree)" --publish --ci-repo $(CURDIR)/../wg12-ci
else
	@echo "Post-processing: Renaming documents to ISO format..."
	@$(PYTHON) $(CURDIR)/scripts/rename_feature_docs.py "$$(cat .feature-build-worktree)/_site" --repo-root $(CURDIR) --root-module $$(cat .feature-build-module)
endif
	@echo ""
	@echo "Quick rebuild complete! Output in: $$(cat .feature-build-worktree)/_site"

# Diff Collection Build Target
# Build a collection of only the documents that differ between two branches
# Usage: make diff_collection [BRANCH=<feature_branch>] [REF=develop]
#        make diff_collection BRANCH=feature/TCSC410303-2823-fix-quotes
#        make diff_collection BRANCH=feature/TCSC410303-2823-fix-quotes REF=main

BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
REF ?= develop

diff_collection:
	@echo "Building diff collection: $(BRANCH) vs $(REF)"
ifeq ($(DO_MAKE-SINGLE-SHELL),yes)
	./scripts/diff-collection-build.sh $(BRANCH) $(REF)
endif
ifeq ($(DO_MAKE-SINGLE-POWERSHELL),yes)
	$(error diff_collection is not yet supported on Windows)
endif
ifeq ($(OS_NAME),macos)
ifneq (,$(filter docker,$(MAKECMDGOALS)))
	@echo "macOS + docker target detected"
	cd "$$(cat .diff-build-worktree)" && time docker run -it -v "$$(pwd):/metanorma" suma:latest suma build metanorma-diff.yml 2>&1 | tee metanorma-diff-log.txt
else
	@echo "macOS detected"
	cd "$$(cat .diff-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-diff.yml 2>&1 | tee metanorma-diff-log.txt
endif
endif
ifeq ($(OS_NAME),linux)
	@echo "linux detected"
	cd "$$(cat .diff-build-worktree)" && BUNDLE_GEMFILE=$(CURDIR)/Gemfile time bundle exec suma build metanorma-diff.yml 2>&1 | tee metanorma-diff-log.txt
endif
	@# Post-process: Rename documents to ISO standard format (no index split)
	@echo "Post-processing: Renaming documents to ISO format..."
	@$(PYTHON) $(CURDIR)/scripts/rename_feature_docs.py "$$(cat .diff-build-worktree)/_site"
	@echo ""
	@echo "Diff collection build complete!"
	@echo ""
	@echo "Output files:"
	@echo "  Documents: $$(cat .diff-build-worktree)/_site/index.html"
	@echo ""
	@echo "To open in browser:"
	@echo "  open $$(cat .diff-build-worktree)/_site/index.html"