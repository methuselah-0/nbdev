nbdev_build_docs_from_org()(
    shopt -s extglob
    local dir nbs_path doc_path lib_name metadatavalue nbformat_minor_value subs
    #set -x
    declare -a Nbdev_Build_Lib_Libs_Order=()
    while [[ -n "$1" ]]; do
	if [[ "$1" == "--build-libs-order" ]]; then
	    shift 1
	    while ([[ ! "$1" =~ ^- ]] && [[ -n "$1" ]]); do
		Nbdev_Build_Lib_Libs_Order+=("$1")
		shift 1
	    done
	elif [[ "$1" == "--dir" ]]; then
	    dir="$2"
	    shift 2
	elif [[ "$1" == "--metadata-value" ]]; then
	    metadatavalue="$2"
	    shift 2
	elif [[ "$1" == "--nbformat_minor" ]]; then
	    nbformat_minor_value="$2"
	    shift 2
	elif [[ "$1" == "--git-src-prefix" ]]; then
	    git_src_prefix="$2"
	    shift 2
	elif [[ "$1" == "--keep-subs" ]]; then
	    subs=yes
	    shift 1	    
	else
	    shift
	fi
    done    
    echo git_src_prefix is "$git_src_prefix"
    echo build order is: "${Nbdev_Build_Lib_Libs_Order[@]}"
    dir="${dir:-.}"
    subs="${subs:-no}"
    nbformat_minor_value="${nbformat_minor_value:-1}"
    echo subs is "$subs"
    echo nbformat_minor is "$nbformat_minor_value"
    echo dir is "$dir"
    [[ -f "${dir}"/settings.ini ]] || { echo "Could not find settings.ini in < ${dir} > or the current directory. You must be in an nbdev git root directory to run nbdev_build_docs_from_org or specify the path with --dir <path_to_nbdev_repo>" && return 1 ; }
    startdir="$(pwd)"
    cd "$dir"
    trap "cd $startdir" RETURN
    trap "cd $startdir" EXIT
    # extra dependencies
    pip install -qqq testpath
    export GEM_HOME="$HOME/gems"
    # this order is important so that jekyll from guix is used when running docs_serve
    export PATH="$HOME/gems/bin:$PATH"
    export LD_LIBRARY_PATH="$GUIX_PROFILE"/lib
    gem install bundler:2.0.2

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
(setq org-use-sub-superscripts nil)
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

    nbs_path="$(grep -E '^nbs_path' "$dir"/settings.ini | cut -f 3 -d ' ')"
    nbs_path_full=$(readlink -f "$dir"/"$nbs_path")
    doc_path="$(grep -E '^doc_path' "$dir"/settings.ini | cut -f 3 -d ' ')"
    doc_path_full=$(readlink -f "$dir"/"$doc_path")
    lib_name="$(grep -E '^lib_name' "$dir"/settings.ini | cut -f 3 -d ' ')"
    #lib_name_full=$(readlink -f "$dir"/"$lib_name")

    # dependencies
    gem install bundler:2.0.2
    # due to warnings like "Ignoring commonmarker-0.17.13 because its extensions are not built. Try: gem pristine commonmarker --version 0.17.1" when running gem install bundler we could install those things too:
    # gem pristine eventmachine --version 1.2.7
    # gem pristine ffi --version 1.13.1
    # gem pristine ffi --version 1.11.3
    # gem pristine http_parser.rb --version 0.6.0
    # gem pristine nokogiri --version 1.10.8
    # gem pristine sassc --version 2.4.0

    bundle install --gemfile="${doc_path_full}"/Gemfile
    
    # Find all org-files to convert
    local -a Files=()
    #mapfile -t Files < <(find "$nbs_path" -name '*.org' -type f)

    # Find all export statements in the org-files, and if there are exports to modules without corresponding org-files, then create a basic such org-file file.
    shopt -s extglob
    set +x
    mapfile -t Files < <(find "$nbs_path" -name '*.org' -type f)
    mapfile -t ExportFiles < <(
	for f in "${Files[@]}"; do
	    mapfile -t ExportLines < <( grep -E '^# export(s|i)? ' "$f")
	    for l in "${ExportLines[@]}"; do
		if [[ "$l" =~ ^#\ export(s|i)?\ (.*)+ ]]; then
		    orgfile="$(dirname "$f")/${BASH_REMATCH[2]}" ; echo "$orgfile" ; fi ; done ; done | sort -u )
    # TODO: CONTINUE: check if ExportFiles already exist, if not create basic org-file with # default_exp <module.submodule> etc.
#     for f in "${ExportFiles[@]}"; do
# 	if [[ ! -f "${f//./\/}".org ]]; then
# 	    fmods="${f##*/}"
# 	    fparentmods="${fmods%.*}"

# 	    cat <<EOF > "${f//./\/}".org
# #+PROPERTY: header-args:python :shebang "#!/usr/bin/env python3" :eval no-export :noweb no-export :mkdirp yes
# #+PROPERTY: header-args:jupyter-python :shebang "#!/usr/bin/env python3" :eval no-export :noweb no-export :mkdirp yes
# #+PROPERTY: header-args:bash :shebang "#!/usr/bin/env bash" :eval no-export :noweb no-export :mkdirp yes

# #+TITLE: ${f##*/}
# #+SUMMARY: The ${f##*/} module

# #+BEGIN_SRC python :noweb-ref "" :session ${f##*/} :tangle ${f##*/}.py
# # default_exp ${f##*/}
# #+END_SRC
# EOF
# 	fi
#     done

    #expfile="apa/bepa.cepa.depa.fepa"
    for expfile in "${ExportFiles[@]}"; do
    expfileBasedir="${expfile//./\/}"
    expfileBasedir="${expfile//./\/}"
    expfiledir="${expfile//./\/}"
    expfiledir="${expfiledir%/*}"
    fparentmods="${expfile%.*}"
    fparentmods="${fparentmods#*/}"

    modpath="${expfile#$nbs_path/$lib_name}"
    modpath="${modpath#*.}"
	mkdir -p "$expfiledir"
	if [[ ! -f "$expfiledir"/"${expfile##*.}" ]]; then
	    #echo stuff > "$expfiledir"/"${expfile##*.}".org; fi
	    expfileNext="${expfile%%/*}/${fparentmods%%.*}".org
	    mod="${expfileNext%.org}"
	    mod="${mod##*.}"
	    the_modpath="${modpath%${mod}*}.$mod"
	    the_modpath="${the_modpath#.}"
	    the_modpath="${the_modpath//\//.}"

	    # TODO: CONTINUE: should print the minimum to-the-left module
	    #modules=${expfile##*/}
	    modules="${expfile/\//.}"
	    modulename="${modules%%.*}"
	    modpath=${expfilepath}
	    cat <<EOF > "$expfiledir"/"${expfile##*.}".org
#+PROPERTY: header-args:python :shebang "#!/usr/bin/env python3" :eval no-export :noweb no-export :mkdirp yes
#+PROPERTY: header-args:jupyter-python :shebang "#!/usr/bin/env python3" :eval no-export :noweb no-export :mkdirp yes
#+PROPERTY: header-args:bash :shebang "#!/usr/bin/env bash" :eval no-export :noweb no-export :mkdirp yes

#+TITLE: ${modules#*/}
#+SUMMARY: The ${modules#*/} module

#+BEGIN_SRC python :noweb-ref "" :session ${modulename} :tangle ${modulename}.py
# default_exp ${modules#*/}
#+END_SRC

EOF
	    unset expfileNext
	fi

	if [[ ! "$fparentmods" == "$expfile" ]] ; then
	    while [[ -n "$fparentmods" ]] ; do
		if [[ -n "$expfileNext" ]]; then
		    expfileNext="${expfileNext%.*}/${fparentmods%%.*}".org
		else
		    expfileNext="${expfile%%/*}/${fparentmods%%.*}".org
		fi
		mod="${expfileNext%.org}"
		mod="${mod##*.}"
		the_modpath="${modpath%${mod}*}.$mod"
		the_modpath="${the_modpath#.}"
		the_modpath="${the_modpath//\//.}"
		the_modpath="${the_modpath#$nbs_path.}"
		the_modpath="${the_modpath#$lib_name.}"
		if [[ ! -f "$expfileNext" ]] ; then
		    #echo stuff > "$expfileNext"; fi
		    modules=${expfileNext##*/}
		    modulename="${modules%%.*}"
		    cat <<EOF > "$expfileNext"
#+PROPERTY: header-args:python :shebang "#!/usr/bin/env python3" :eval no-export :noweb no-export :mkdirp yes
#+PROPERTY: header-args:jupyter-python :shebang "#!/usr/bin/env python3" :eval no-export :noweb no-export :mkdirp yes
#+PROPERTY: header-args:bash :shebang "#!/usr/bin/env bash" :eval no-export :noweb no-export :mkdirp yes

#+TITLE: ${the_modpath}
#+SUMMARY: The ${the_modpath} module

#+BEGIN_SRC python :noweb-ref "" :session ${modulename} :tangle ${modulename}.py
# default_exp ${the_modpath}
#+END_SRC

EOF
		    fi
		if [[ ! "$fparentmods" == "${fparentmods#*.}" ]] ; then
		    fparentmods="${fparentmods#*.}"
		else
		    break ; fi ; done ; fi; done

    # Re-read the list of org-files.
    mapfile -t Files < <(find "$nbs_path" -name '*.org' -type f)
    set -x
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
    emacs --batch -l "$initfile" $(printf -- '--visit %s -f org-org-export-to-org ' "${Files[@]//.org/_temp.org}") --kill || { echo failed to export to org-file ; return 1 ; }
    echo DONE

    for f in "${Files[@]//.org/_temp.org.org}"; do
	mv "${f%.org}" "${f%%.org*}"
	mv "$f" "${f%.org}"; done
    
    echo CONVERTING TO IPYNB "${Files[@]//.org/_temp.org}"
    emacs --batch -l "$initfile" $(printf -- '--visit %s -f ox-ipynb-export-to-ipynb-file ' "${Files[@]//.org/_temp.org}") --kill  || { echo failed to export to ipynb-file ; return 1 ; }
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
	# Fix the metadata
	key="metadata"
	value='{"kernelspec":{"display_name":"Python 3","language":"/gnu/store/11l2qmzfgsp7k345mv6x1vn64q8330kw-python-wrapper-3.8.2/bin/python","name":"python3"},"language_info":{"codemirror_mode":{"name":"ipython","version":3},"file_extension":".py","mimetype":"text/x-python","name":"python","nbconvert_exporter":"python","pygments_lexer":"ipython3","version":"3.8.2"},"org":null}'
	value="${metadatavalue:-$value}"
	jq -Mcn --unbuffered --arg k "$key" --argjson v "$value" --argjson o "$(jq -c . $f)" ' $o + { ( $k ) : $v } ' | sponge "$f"
	key=nbformat_minor
	value="${nbformat_minor_value}"
	jq -Mcn --unbuffered --arg k "$key" --argjson v "$value" --argjson o "$(jq -c . $f)" ' $o + { ( $k ) : $v } ' | sponge "$f"
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
    # echo Adding additional IPYNBS: "${AdditionalIPYNBS[@]%.*}"
    # set -x
    # for ((i=0;i<${#AdditionalIPYNBS[@]};i+=1)); do
    # 	addipynb="${AdditionalIPYNBS[$i]%.*}"
    # 	addipynb_dir="${AdditionalIPYNBS_dirs[$i]}"
    # 	addipynb_org="${AdditionalIPYNBS_orgs[$i]}"
    # 	addipynb_rel="${addipynb#$addipynb_dir/}"
    # 	shopt -s globstar
    # 	if ! grep "# default_exp ${addipynb_rel//\//.}" &>/dev/null < <(cat "$nbs_path"/*.ipynb | jq -rs .[].cells[].source[]); then
    # 	    # a :tangle something.py without ipynb file shouldnt add extra .ipynb file unless we have special export X as well.
    # 	    if grep -E "^#\ export(i|s)?\ ${addipynb_rel//\//.}" < <(cat "$nbs_path"/*.ipynb | jq -rs .[].cells[].source[]); then
    # 	        title_org_header="${addipynb##*/}"
    # 	    	title_org_source_header=$(grep -iE '^#\+TITLE: ' "${addipynb_org}" | head -n 1 | cut -f 2- -d ' ')

    # 		summary_org_header="see $title_org_source_header"
    # 		Tempfiles+=("${addipynb}_temp.ipynb")
    # 		#[[ -e "${addipynb}_temp.ipynb" ]] && rm "${addipynb}_temp.ipynb"
		
    # 		jq -n --argjson a "{\"cells\":[{\"cell_type\":\"markdown\",\"metadata\":{},\"source\":[\"# ${title_org_header%.*}\n\",\"\n\",\"> $summary_org_header\"]},{\"cell_type\":\"code\",\"execution_count\":1,\"metadata\":{},\"outputs\":[],\"source\":[\"# default_exp ${addipynb_rel//\//.}\"]}]}" --argjson b "{${metadata_etc}}" '$a + $b'  > "${addipynb}_temp.ipynb"

    # 		# add a link to it in the path to the notebooks (nbs_path)
    # 		addipynb_full=$(readlink -f "$addipynb"_temp.ipynb)
    #  		rel_path="${addipynb_full#$nbs_path_full/}"
    #  		ln -s "${rel_path}" "${nbs_path}"/ ; fi; fi; done
    # set +x
    
    #echo prepending titles and summaries
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
	    # removing this for testing
	    #jq --argjson a "$title_json" '.cells = ([$a] + .cells)' "${f}_temp.ipynb" | sponge "${f}_temp.ipynb";
	fi;

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

    #script(){ shopt -s extglob ; mapfile -t DocFiles < <(find "$doc_path" -iname '*_temp.html') ; CurrentRaw="" ; for f in "${DocFiles[@]}" ; do if [[ "$subs" == no ]]; then  sed -i -e 's/<sub>/_/g' -e  's/<\/sub>//g' "$f" ; fi ; while read -r line ; do if [[ "$line" =~ '{% raw %}' ]] ; then CurrentRaw="${BASH_REMATCH[0]}" ; elif [[ "$line" =~ '{% endraw %}' ]] ; then if testfile=$(grep -iPo '(?<=>&quot;pytest ).+(?=.py&quot;<)' < <(grep -E '<div class="input_area">.*subprocess.*check_output' <<<"${CurrentRaw//$'\n'/}")) ; then for ef in "${ExportFiles[@]}" ; do if [[ "$ef" =~ "${testfile//\//.}"$ ]]; then mod="${ef##*.}"; declare -p CurrentRaw > /tmp/debug ; echo "${CurrentRaw}{% endraw %}" >> "$doc_path"/"${mod}"_temp.html ; fi ; done ; elif grep -q -i 'class="source_link"' <<<"${CurrentRaw//$'\n'/}"; then printf '%s\n' "found source link lines:" "${CurrentRaw}${BASH_REMATCH[0]}" "in $f" ; mod1=$(grep -oP '(?<=href=)".*(?=( class="source_link"))' <<<"${CurrentRaw//$'\n'/}" ); echo mod1 is "$mod1" ; mod2="${mod1##*/}" ; echo mod2 is "$mod2" ; mod3="${mod2%.*}" ; echo mod3 is "${mod3}" ; mod="$mod3" ; echo mod is "$mod" ; if ! grep -qF "${CurrentRaw//$'\n'/}${BASH_REMATCH[0]}" < <(< "$doc_path"/${mod}_temp.html tr -d $'\n') ; then echo could not find "${CurrentRaw}${BASH_REMATCH[0]}" in "$doc_path"/${mod}_temp.html so adding it ; echo "${CurrentRaw}${BASH_REMATCH[0]}" >> "$doc_path"/${mod}_temp.html ; fi ; echo found "${CurrentRaw}${BASH_REMATCH[0]}" already in "$doc_path"/${mod}_temp.html so not adding it ; CurrentRaw="" ; fi ; else CurrentRaw+="$line"$'\n' ; fi ; done < "$f" ; done ; } ;
    clean_fix_script(){ shopt -s extglob ; mapfile -t DocFiles < <(find "$doc_path" -iname '*_temp.html') ; CurrentRaw="" ; for f in "${DocFiles[@]}" ; do HLevel="" ; declare -i LineNum=0 ; declare -i CurrentRawStartLineNum=0 ; declare -i CurrentRawEndLineNum=0 ; while read -r line ; do LineNum+=1 ; if hlevel=$(grep -oP '(?<=(^<h))[0-9](?=( id=\".*<a class=\"anchor-link\" href=\"))' <<<"$line") ; then HLevel="$hlevel" ; fi ; if [[ "$line" =~ '{% raw %}' ]] ; then CurrentRaw="${BASH_REMATCH[0]}" ; CurrentRawStartLineNum=$LineNum ; elif [[ "$line" =~ '{% endraw %}' ]] ; then CurrentRawEndLineNum="$LineNum" ; if testfile=$(grep -iPo '(?<=>&quot;pytest ).+(?=.py&quot;<)' < <(grep -E '<div class="input_area">.*subprocess.*check_output' <<<"${CurrentRaw//$'\n'/}")) ; then for ef in "${ExportFiles[@]}" ; do if [[ "$ef" =~ "${testfile//\//.}"$ ]]; then mod="${ef##*.}"; declare -p CurrentRaw > /tmp/debug ; if ! grep -qF "${CurrentRaw//$'\n'/}{% endraw %}" < <(< "$doc_path"/${mod}_temp.html tr -d $'\n') ; then echo "${CurrentRaw}{% endraw %}" >> "$doc_path"/"${mod}"_temp.html ; fi ; fi; done ; elif grep -q -i 'class="source_link"' <<<"${CurrentRaw//$'\n'/}"; then printf '%s\n' "found source link lines:" "${CurrentRaw}${BASH_REMATCH[0]}" "in $f" ; mod1=$(grep -oP '(?<=href=)".*(?=( class="source_link"))' <<<"${CurrentRaw//$'\n'/}" ); echo mod1 is "$mod1" ; mod2="${mod1##*/}" ; echo mod2 is "$mod2" ; mod3="${mod2%.*}" ; echo mod3 is "${mod3}" ; mod="$mod3" ; echo mod is "$mod" ; if ! grep -qF "${CurrentRaw//$'\n'/}${BASH_REMATCH[0]}" < <(< "$doc_path"/${mod}_temp.html tr -d $'\n') ; then echo could not find "${CurrentRaw}${BASH_REMATCH[0]}" in "$doc_path"/${mod}_temp.html so adding it ; echo "${CurrentRaw}${BASH_REMATCH[0]}" >> "$doc_path"/${mod}_temp.html ; declare -i NewHLevel=$((HLevel+1)) ; echo Changing HLevel in original file "$f" to current HLevel $HLevel plus 1 $NewHLevel ; sed -i "$CurrentRawStartLineNum,$CurrentRawEndLineNum s/<h[0-9] id=\"/<h$NewHLevel id=\"/g" "$f" ; sed -i "$CurrentRawStartLineNum,$CurrentRawEndLineNum s/<\/a><\/h[0-9]>/<\/a><\/h$NewHLevel>/g" "$f"; fi ; echo found "${CurrentRaw}${BASH_REMATCH[0]}" already in "$doc_path"/${mod}_temp.html so not adding it ; CurrentRaw="" ; fi ; else CurrentRaw+="$line"$'\n' ; fi ; done < "$f" ; done ; }

    if [[ -n "${Nbdev_Build_Lib_Libs_Order[@]}" ]]; then
	# needed to remake the lib directory if it doesn't exist.
	#nbdev_build_lib &>/dev/null
	declare -a NBs=("${Nbdev_Build_Lib_Libs_Order[@]}")
	for  ((i=0;i<${#NBs[@]};i++)) ; do if [[ "${#i}" -eq 1 ]] ; then mv "$nbs_path_full"/"${NBs[$i]}" "$nbs_path_full"/0"${i}"_"${NBs[$i]}" ; else mv "$nbs_path_full"/"${NBs[$i]}" "$nbs_path_full"/"${i}"_"${NBs[$i]}" ; fi ; done

	if (nbdev_build_lib); then
	    rm "$doc_path"/*_temp.html; fi
	# for nb in "${Nbdev_Build_Lib_Libs_Order[@]}"; do
	#     echo Converting the notebook: "$nb"
	#     nbdev_build_lib --fname "$nb" &
	#     wait
	#     [[ ! "$?" == "0" ]] && return 1
	#     done
    else
	if (nbdev_build_lib); then
	    echo Continuing with building docs
	    rm "$doc_path"/*_temp.html
	else
	    # try a second time
	    if ! (nbdev_build_lib) ; then
		echo Failed to build lib. Not continuing with building docs.
		echo "If you are unable to build libraries with nbdev_build_lib it may be because you have internal dependencies between notebooks and nbdev_build_lib tries to build in parallel, therefore try nbdev_build_lib --fname <lib>.ipynb in the order of core libraries to libraries with the most dependencies on other modules. You can then pass --build-libs-order to this script and rerun it."
		return 1
	    fi
	    rm "$doc_path"/*_temp.html
	fi
    fi

    if [[ -n "${Nbdev_Build_Lib_Libs_Order[@]}" ]]; then
	# for nb in "${Nbdev_Build_Lib_Libs_Order[@]}"; do
	#     echo Converting the notebook: "$nb"
	#     nbdev_build_lib --fname "$nb" &
	#     wait
	#     [[ ! "$?" == "0" ]] && return 1
	# done

	# undo earlier changes to see if it fixes the nbdev_build_docs bug
	unset LD_LIBRARY_PATH
	unset GEM_HOME
	#PATH="$HOME/gems/bin:$PATH"
	PATH="${PATH#$HOME/gems/bin:}"

	# this cd is apparently necessary when exporting classes
	cd "$nbs_path"	
	if ! (nbdev_build_docs --force_all '*'); then
	    echo failed building docs, trying again after some mv AND some cd
	    #echo some weird bug, mv'ing 1 file should be sufficient though
	    set -x
	    for  ((i=0;i<${#NBs[@]};i++)) ; do
		if [[ "${#i}" -eq 1 ]] ; then
		    mv "$nbs_path_full"/0"${i}"_"${NBs[$i]}" "$nbs_path_full"/0"${i}"_"${NBs[$i]}"_0123456789
		    mv "$nbs_path_full"/0"${i}"_"${NBs[$i]}"_0123456789 "$nbs_path_full"/0"${i}"_"${NBs[$i]}"
		    break
		else
		    mv "$nbs_path_full"/"${i}"_"${NBs[$i]}" "$nbs_path_full"/"${i}"_"${NBs[$i]}"_0123456789
		    mv "$nbs_path_full"/"${i}"_"${NBs[$i]}"_0123456789 "$nbs_path_full"/"${i}"_"${NBs[$i]}"
		fi ; done
	    set +x
	    if ! (nbdev_build_docs --force_all '*'); then
		return 1
	    fi
	fi
    elif ! (nbdev_build_docs --force_all '*'); then
	echo failed building docs
	return 1
    fi
    cd "$dir"
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
    pwd
    cd "$startdir"
    clean_fix_script
    #shopt -s extglob ; mapfile -t DocFiles < <(find "$doc_path" -iname '*_temp.html') ; CurrentRaw="" ; for f in "${DocFiles[@]}" ; do HLevel="" ; declare -i LineNum=0 ; declare -i CurrentRawStartLineNum=0 ; declare -i CurrentRawEndLineNum=0 ; while read -r line ; do LineNum+=1 ; if hlevel=$(grep -oP '(?<=(^<h))[0-9](?=( id=\".*<a class=\"anchor-link\" href=\"))' <<<"$line") ; then HLevel="$hlevel" ; fi ; if [[ "$line" =~ '{% raw %}' ]] ; then CurrentRaw="${BASH_REMATCH[0]}" ; CurrentRawStartLineNum=$LineNum ; elif [[ "$line" =~ '{% endraw %}' ]] ; then CurrentRawEndLineNum="$LineNum" ; if testfile=$(grep -iPo '(?<=>&quot;pytest ).+(?=.py&quot;<)' < <(grep -E '<div class="input_area">.*subprocess.*check_output' <<<"${CurrentRaw//$'\n'/}")) ; then for ef in "${ExportFiles[@]}" ; do if [[ "$ef" =~ "${testfile//\//.}"$ ]]; then mod="${ef##*.}"; declare -p CurrentRaw > /tmp/debug ; echo "${CurrentRaw}{% endraw %}" >> "$doc_path"/"${mod}"_temp.html ; fi ; done ; elif grep -q -i 'class="source_link"' <<<"${CurrentRaw//$'\n'/}"; then printf '%s\n' "found source link lines:" "${CurrentRaw}${BASH_REMATCH[0]}" "in $f" ; mod1=$(grep -oP '(?<=href=)".*(?=( class="source_link"))' <<<"${CurrentRaw//$'\n'/}" ); echo mod1 is "$mod1" ; mod2="${mod1##*/}" ; echo mod2 is "$mod2" ; mod3="${mod2%.*}" ; echo mod3 is "${mod3}" ; mod="$mod3" ; echo mod is "$mod" ; if ! grep -qF "${CurrentRaw//$'\n'/}${BASH_REMATCH[0]}" < <(< "$doc_path"/${mod}_temp.html tr -d $'\n') ; then echo could not find "${CurrentRaw}${BASH_REMATCH[0]}" in "$doc_path"/${mod}_temp.html so adding it ; echo "${CurrentRaw}${BASH_REMATCH[0]}" >> "$doc_path"/${mod}_temp.html ; declare -i NewHLevel=$((HLevel+1)) ; echo Changing HLevel in original file "$f" to current HLevel $HLevel plus 1 $NewHLevel ; sed -i "$CurrentRawStartLineNum,$CurrentRawEndLineNum s/<h[0-9] id=\"/<h$NewHLevel id=\"/g" "$f" ; sed -i "$CurrentRawStartLineNum,$CurrentRawEndLineNum s/<\/a><\/h[0-9]>/<\/a><\/h$NewHLevel>/g" "$f"; fi ; echo found "${CurrentRaw}${BASH_REMATCH[0]}" already in "$doc_path"/${mod}_temp.html so not adding it ; CurrentRaw="" ; fi ; else CurrentRaw+="$line"$'\n' ; fi ; done < "$f" ; done
    mapfile -t DocFiles < <(find "$doc_path_full" -iname '*_temp.html') ; CurrentRaw="" ; for f in "${DocFiles[@]}" ; do if [[ "$subs" == "no" ]]; then  sed -i -e 's/<sub>/_/g' -e  's/<\/sub>//g' "$f" ; fi ; done
    str2arr(){ local string="$1" ; [[ "${string}" =~ ${string//?/(.)} ]]; local -a arr=("${BASH_REMATCH[@]:1}"); printf '%s' "(${arr[*]@Q})" ; }
    sed_esc_rep(){ printf '%s' "${1}" | sed -e 's/[\/&]/\\&/g' ;}

    for f in "${DocFiles[@]}"; do
	libname="$lib_name"
	git_src_prefix="${git_src_prefix%/}/" ; rep=$(sed_esc_rep "$git_src_prefix") ; sed -i -e "s/<\/code><a href=\"\($libname.*\.py#L[0-9]\+\)\" class=\"source_link\"/<\/code><a href=\"$rep\1\" class=\"source_link\"/g" "$f"
    done
    
    # mapfile -t DocFiles < <(find "$doc_path" -iname '*_temp.html') ;
    # CurrentRaw="" ;
    # for f in "${DocFiles[@]}" ; do
    # 	while read -r line ; do
    # 	    if [[ "$line" =~ '{% raw %}' ]] ; then
    # 		CurrentRaw="${BASH_REMATCH[0]}" ;
    # 	    elif [[ "$line" =~ '{% endraw %}' ]] ; then
    # 		if grep -q -i 'class="source_link"' <<<"$CurrentRaw"; then
    # 		    mod=$(grep -oP '"http.*(?=( class="source_link"))' <<<"$CurrentRaw" );
    # 		    mod="${mod##*/}" ;
    # 		    mod="${mod%.*}" ;
    # 		    mod="${mod}" ;
    # 		    if ! grep -qF "${CurrentRaw}${BASH_REMATCH[0]}" "$doc_path"/${mod}_temp.html ;
    # 		    then echo "${CurrentRaw}${BASH_REMATCH[0]}" >> "$doc_path"/${mod}_temp.html ; fi ; CurrentRaw="" ; fi ; else CurrentRaw+="$line" ; fi ; done < "$f" ; done

)
nbdev_build_docs_from_org "$@"
