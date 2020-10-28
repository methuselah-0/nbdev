nbdev_build_docs_from_org(){
    # extra dependencies
    pip install -qqq testpath
    export GEM_HOME="$HOME/gems"
    # this order is important so that jekyll from guix is used when running docs_serve
    export PATH="$PATH:$HOME/gems/bin"
    export LD_LIBRARY_PATH="$GUIX_PROFILE"/lib
    gem install bundler -v 2.0.2

    local initfile=$(mktemp ~/.emacs.d/tmp.XXXXXXXX)
    local init=$(cat <<EOF
;; Added by Package.el.  This must come before configurations of
;; installed packages.  Don't delete this line.  If you don't want it,
;; just comment it out by adding a semicolon to the start of the line.
;; You may delete these explanatory comments.
(require 'package)
;; optional. makes unpure packages archives unavailable
(setf package-archives nil)
(setf package-enable-at-startup nil)
(package-initialize)
(add-to-list 'load-path "~/.emacs.d/elisp-files/")
(progn (cd "~/.emacs.d/elisp-files/")
              (normal-top-level-add-subdirs-to-load-path))
(add-to-list 'package-archives
	     '("melpa" . "https://melpa.org/packages/")
	     '("org" . "https://orgmode.org/elpa/")
       )
  (when (< emacs-major-version 24)
    ;; For important compatibility libraries like cl-lib
    (add-to-list 'package-archives '("gnu" . "http://elpa.gnu.org/packages/")))
(require 'jupyter)
(require 'ob-jupyter)
(add-to-list 'org-src-lang-modes '("jupyter" . fundamental))
(require 'ox-ipynb)
(org-babel-do-load-languages
 'org-babel-load-languages
 '((python . t)
   (dot . t)
   (latex . t)
   (shell . t)
   (jupyter . t)))
(setq org-confirm-babel-evaluate nil)
(org-babel-jupyter-override-src-block "python")
(setq org-use-sub-superscripts "{}")
(setq geiser-default-implementation 'guile)
(setq org-src-preserve-indentation t)
(require 'org-re-reveal)
(custom-set-variables
'(safe-local-variable-values
   (quote
    ((org-src-preserve-indentation . t)
     (org-my-aNumber . 32)
     (org-my-foo . bar)
     (org-babel-noweb-wrap-end . \">>)
     (org-babel-noweb-wrap-start . \")
     (org-confirm-babel-evaluate)
     (org-babel-noweb-wrap-end . ">>#")
     (org-babel-noweb-wrap-start . "#<<")
     (eval modify-syntax-entry 43 "'")
     (eval modify-syntax-entry 36 "'")
     (eval modify-syntax-entry 126 "'")))))
EOF
	  )
    echo "$init" > "$initfile"

    local dir nbs_path doc_path lib_name
    dir="${1:-.}"
    if [[ ! -e "${dir}/settings.ini" ]]; then echo no settings.ini found in "$dir". Exiting; fi
    nbs_path="$(grep -E '^nbs_path' "$dir"/settings.ini | cut -f 3 -d ' ')"
    nbs_path_full=$(readlink -f "$dir"/"$nbs_path")
    doc_path="$(grep -E '^doc_path' "$dir"/settings.ini | cut -f 3 -d ' ')"
    doc_path_full=$(readlink -f "$dir"/"$doc_path")
    lib_name="$(grep -E '^lib_name' "$dir"/settings.ini | cut -f 3 -d ' ')"
    #lib_name_full=$(readlink -f "$dir"/"$lib_name")

    # dependencies
    gem install bundler:2.0.2
    bundle install "${doc_path_full}"/Gemfile
    
    # Find all org-files to convert
    local -a Files=()
    mapfile -t Files < <(find "$nbs_path" -name '*.org' -type f)

    # Fix the src_block python to src_block jupyter-python needed for
    # ox-ipynb export, then export.
    local f fdir
    local -a More
    local -a AdditionalIPYNBS=()
    local -a AdditionalIPYNBS_dirs=()
    local -a AdditionalIPYNBS_orgs=()
    for f in "${Files[@]}" ; do
	#set -x
	cp "$f" "${f%.org}_temp.org"
	echo running sed command: sed -i 's/^#+BEGIN_SRC python/#+BEGIN_SRC jupyter-python/g' "${f%.org}_temp.org"
	sed -i 's/^#+BEGIN_SRC python/#+BEGIN_SRC jupyter-python/g' "${f%.org}_temp.org"
	echo running sed command: sed -i 's/^#+begin_src python/#+BEGIN_SRC jupyter-python/g' "${f%.org}_temp.org"
	sed -i 's/^#+begin_src python/#+BEGIN_SRC jupyter-python/g' "${f%.org}_temp.org"

	# edit the default setting for jupyter-python and python
	echo running sed command: sed -i 's/#+PROPERTY:\ header-args:python.*/& :noweb yes/g' "${f%.org}_temp.org"
	sed -i 's/#+PROPERTY:\ header-args:python.*/& :noweb yes/g' "${f%.org}_temp.org"
	echo running sed command: sed -i 's/#+PROPERTY:\ header-args:jupyter-python.*/& :noweb yes/g' "${f%.org}_temp.org"
	sed -i 's/#+PROPERTY:\ header-args:jupyter-python.*/& :noweb yes/g' "${f%.org}_temp.org"

	# find all :tangle targets that don't have it's own org-file,
	# since they must be created in order to use
	# nbdev_build_lib. Removing parenthesises.
	fdir=$(dirname "$f"); fdir="${fdir//\//\\/}"
	local -a More=()
	mapfile -t More < <(grep -oP '(?<=:tangle )\S+(?=(\n|\ ))' "$f" | sed 's/\"//g' | sed "s/.*/$fdir\/&/g" | sort -u)
	local m
	for m in "${More[@]}"; do
	    AdditionalIPYNBS_orgs+=("$f")
	    AdditionalIPYNBS_dirs+=("$fdir")
	    AdditionalIPYNBS+=( "${m}" ); done
    done
    mapfile -t AdditionalIPYNBS < <(printf '%s\n' "${AdditionalIPYNBS[@]}" | sort -u )
    # TODO: add this perhaps - note that noweb is expanded
    local nowebstuff=$( cat <<'EOF'
* COMMENT babel settings
  
# Local Variables:
# org-babel-noweb-wrap-start: "#<<"
# org-babel-noweb-wrap-end: ">>#"
# org-confirm-babel-evaluate: nil
# org-src-preserve-indentation: t)
# org-my-foo: bar
# org-my-aNumber: 32
# End:
EOF
	  )
    for f in "${Files[@]//.org/_temp.org}"; do
	echo "$nowebstuff" >> "$f"; done
	#mv "${f%.org}" "${f%%.org*}"
	#mv "$f" "${f%.org}"; done

    # Removing old symlinks
    mapfile -t OldSymlinks < <(find "$nbs_path" -type l)
    for f in "${OldSymlinks[@]}"; do
	rm "$f"; done

    echo CONVERTING TO ORG WITH NOWEB "${Files[@]//.org/_temp.org}"
    emacs --batch -l "$initfile" $(printf -- '--visit %s -f org-org-export-to-org ' "${Files[@]//.org/_temp.org}") --kill
    echo DONE

    for f in "${Files[@]//.org/_temp.org.org}"; do
	mv "${f%.org}" "${f%%.org*}"
	mv "$f" "${f%.org}"; done
    
    echo CONVERTING TO IPYNB "${Files[@]//.org/_temp.org}"
    emacs --batch -l "$initfile" $(printf -- '--visit %s -f ox-ipynb-export-to-ipynb-file ' "${Files[@]//.org/_temp.org}") --kill
    echo DONE

    # since nbdev_test_nbs or nbdev_build_lib doesn't seem to be able to pick up nbs in subdirs of doc_path
    # we must symlink to them
    local rel_path f_full
    set -x
    echo Creating necessary symlinks for: "${Files[@]//.org/_temp.ipynb}"
    for f in "${Files[@]//.org/_temp.ipynb}"; do

	f_full="$(readlink -f "$f")"
	# Create a symlink in nbs_path unless it exists directly in that dir already
	[[ ! -e "$nbs_path_full"/"${f_full##*/}" ]] && {
     	    rel_path="${f_full#$nbs_path_full/}"
     	    ln -s "${rel_path}" "${nbs_path}"/
	}
    done
    echo "...DONE"
    set +x

    # If we can't find a default_exp in any of the ipynb files for a
    # target module (which is identified via :tangle X lines), then we
    # must create one, so that #export X comments from other modules
    # (or org-files) works.
    local metadata_etc=$( cat <<'EOF'
  "metadata": {
    "org": null,
    "kernelspec": {
      "display_name": "Python 3",
      "language": "python",
      "name": "python3"
    },
    "language_info": {
      "codemirror_mode": {
        "name": "ipython",
        "version": 3
      },
      "file_extension": ".py",
      "mimetype": "text/x-python",
      "name": "python",
      "nbconvert_exporter": "python",
      "pygments_lexer": "ipython3",
      "version": "3.5.2"
    }
  },
  "nbformat": 4,
  "nbformat_minor": 0
EOF
	  )
    
    local -a Tempfiles=()    
    echo Adding additional IPYNBS: "${AdditionalIPYNBS[@]%.*}"
    set -x
    for ((i=0;i<${#AdditionalIPYNBS[@]};i+=1)); do
	addipynb="${AdditionalIPYNBS[$i]%.*}"
	addipynb_dir="${AdditionalIPYNBS_dirs[$i]}"
	addipynb_org="${AdditionalIPYNBS_orgs[$i]}"
	addipynb_rel="${addipynb#$addipynb_dir/}"
	shopt -s globstar
    	if ! grep "# default_exp ${addipynb_rel//\//.}" &>/dev/null < <(cat "$nbs_path"/*.ipynb | jq -rs .[].cells[].source[]); then
	    # a :tangle something.py without ipynb file shouldnt add extra .ipynb file unless we have special export X as well.
	    if grep -E "^#\ export(i|s)?\ ${addipynb_rel//\//.}" < <(cat "$nbs_path"/*.ipynb | jq -rs .[].cells[].source[]); then
	        title_org_header="${addipynb##*/}"
	    	title_org_source_header=$(grep -iE '^#\+TITLE: ' "${addipynb_org}" | head -n 1 | cut -f 2- -d ' ')

    		summary_org_header="see $title_org_source_header"
    		Tempfiles+=("${addipynb}_temp.ipynb")
		#[[ -e "${addipynb}_temp.ipynb" ]] && rm "${addipynb}_temp.ipynb"
		
		jq -n --argjson a "{\"cells\":[{\"cell_type\":\"markdown\",\"metadata\":{},\"source\":[\"# ${title_org_header%.*}\n\",\"\n\",\"> $summary_org_header\"]},{\"cell_type\":\"code\",\"execution_count\":1,\"metadata\":{},\"outputs\":[],\"source\":[\"# default_exp ${addipynb_rel//\//.}\"]}]}" --argjson b "{${metadata_etc}}" '$a + $b'  > "${addipynb}_temp.ipynb"

		# add a link to it in the path to the notebooks (nbs_path)
		addipynb_full=$(readlink -f "$addipynb"_temp.ipynb)
     		rel_path="${addipynb_full#$nbs_path_full/}"
     		ln -s "${rel_path}" "${nbs_path}"/ ; fi; fi; done
    set +x
    
    echo prepending titles and summaries
    # Prepend titles and summaries
    local -a Dirs=()    
    for f in "${Files[@]%.org}"; do
	local title_org_header=""
	title_org_header=$(grep -iE '^#\+TITLE: ' "${f}.org" | head -n 1 | cut -f 2- -d ' ')
	summary_org_header=$(grep -iE '^#\+SUMMARY: ' "${f}.org" | head -n 1 | cut -f 2- -d ' ')
	if [[ -n "$title_org_header" ]]; then
	    [[ -n "$summary_org_header" ]] && summary_org_header="> $summary_org_header"
	    title_json="{\"cell_type\":\"markdown\",\"metadata\":{},\"source\":[\"# $title_org_header\n\",\"\n\",\"$summary_org_header\"]}"
	    jq --argjson a "$title_json" '.cells = ([$a] + .cells)' "${f}_temp.ipynb" | sponge "${f}_temp.ipynb"
	    jq --argjson a "$title_json" '.cells = ([$a] + .cells)' "${f}_temp.ipynb" | sponge "${f}_temp.ipynb"; fi;

	# Check for .ob-jupyter directories related to the org-files	
	if [[ -d "${f%/*}/.ob-jupyter" ]]; then
	    mkdir -p "$nbs_path_full"/.ob-jupyter
	    cp "${f%/*}/.ob-jupyter"/* "$nbs_path_full"/.ob-jupyter/
	    Dirs+=( "${f%/*}/.ob-jupyter"); fi
    done
    mapfile -t Dirs < <(printf '%s\n' "${Dirs[@]}" | sort -u)
    
    # Remove the temporary org-files
    for f in "${Files[@]%.org}"; do
	local fi
	for fi in "${f}_temp.org" "${f}_temp"; do
	    [[ -e "$fi" ]] && {
		echo deleting "$fi"
		rm "$fi"
	    }
	done
    done
    
    rm "$initfile"
    # nbdev_build_lib and docs requires an index.ipynb file in the nbs_path directory
    echo running: mv "$doc_path_full"/index_temp.ipynb "$doc_path_full"/index.ipynb
    mv "$nbs_path_full"/index_temp.ipynb "$nbs_path_full"/index.ipynb
    
    # Rebuild the nbdev lib so that the jekyll-website have correct
    # source-references
    rm -r "$dir"/"$lib_name" ;

    if nbdev_build_lib; then echo Continuing with building docs
    else
	Failed to build lib. Not continuing with building docs.
	return 1
    fi

    cd "$dir" ; nbdev_build_docs ; cd -

    # copy over any .ob-jupyter directories to jekyll docs and nbdev
    # lib directories. Since jekyll doesnt handle hidden directories
    # (starting with '.') we fix that in this process.
    set -x    
    local d
    for d in "${Dirs[@]%.ob-jupyter}"; do
	local subpath="${d#*$nbs_path}"
	[[ "$subpath" == "/" ]] && subpath=.
	local newpath="${doc_path_full}"/"${subpath}"
	mkdir -p "${newpath}"
	if [[ -d "${newpath}"/.ob-jupyter ]]; then
	    rm -rf "${newpath}"/.ob-jupyter; fi
	cp -a "${d}".ob-jupyter "${newpath}"/ob-jupyter
    done
    shopt -s globstar ; sed -i 's/\/.ob-jupyter\//\/ob-jupyter\//g' "$doc_path_full"/**/*.html
    set +x
}
nbdev_build_docs_from_org
