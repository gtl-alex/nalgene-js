fs = require 'fs'
minimist = require 'minimist'
{randomChoice, flatten, splitToken, asSentence} = require './helpers'
parse = require './parse'

# Main generation
# ------------------------------------------------------------------------------

# A sentence is generated from a grammar filename, context, and optional entry key

module.exports = generate = (root, context={}, entry_key='%', options={}) ->
    {skip_duplicates} = options
    entry = root.get(entry_key)
    if !entry?
        throw new Error 'No such phrase on root: ' + entry_key

    phrases = expandPhrases entry, root

    # Filter expanded phrases to those that can be resolved with the given context
    notInContext = (token) ->
        token.match(/^\$/) and !context[token]?

    numNotInContext = (tokens) ->
        n = 0
        used = {}
        for token in flatten(tokens.map(splitToken))
            if notInContext token
                n += 1
            else if inContext(token) and skip_duplicates
                if used[token]
                    n += 1
                else
                    used[token] = true
        return n

    inContext = (token) ->
        token.match(/^\$/) and context[token]?

    numInContext = (tokens) ->
        n = 0
        used = {}
        for token in flatten(tokens.map(splitToken))
            if inContext token
                if !used[token] or !skip_duplicates
                    used[token] = true
                    n += 1
        return n

    good_phrases = phrases.filter (tokens) ->
        numNotInContext(tokens) == 0

    if good_phrases.length == 0
        throw new Error 'No viable phrases for entry ' + entry_key + ' with context: ' + JSON.stringify context

    # Choose a phrase that uses the most of the context
    good_phrases.sort (a, b) -> numInContext(b) - numInContext(a)
    num_in_best = numInContext(good_phrases[0])
    best_phrases = []
    for phrase in good_phrases
        if numInContext(phrase) == num_in_best
            best_phrases.push phrase
        else
            break
    phrase = randomChoice best_phrases

    # console.log "[generate total=#{phrases.length} good=#{good_phrases.length} best=#{best_phrases.length} used=#{num_in_best}]"
    return asSentence expandTokens(phrase, root, context)

expandPhrases = (phrase, root) ->
    # console.log '[expandPhrases]', phrase.key
    flatten phrase.allLeaves().map (leaf) -> expandPhrase leaf.key, root

# Expand phrase takes a root node and descends into every possible phrasing by
# expanding only phrase (%) nodes. It returns a list of flat phrases (token lists)

expandPhrase = (key, root) ->
    # console.log '[expandPhrase]', key
    expansions = [[]]
    tokens = key.split(' ')

    for token in tokens

        # For sub-phrases we duplicate existing expansions with every possible sub-expansion
        if token.match /^%/
            new_expansions = []
            token = token.split('|')[0]
            sub_phrase = root.get(token)
            if !sub_phrase
                throw new Error 'No such phrase on root: ' + token
            for e in expandPhrases sub_phrase, root
                for expansion in expansions
                    new_expansions.push expansion.concat e
            expansions = new_expansions

        # Non-phrase tokens are added directly to the end of expansions
        else
            for expansion in expansions
                expansion.push token

    return expansions

# Expand other tokens with context

expandTokens = (tokens, root, context) ->
    # console.log '[expandTokens]', tokens
    expanded = []
    chosen_synonyms = {}

    for token in tokens

        # Variable (value directly from context)
        if token.match /^\$/
            expanded.push context[token]

        # Synonym (randomly chosen)
        else if token.match /^~/
            if token.match /\?$/
                if Math.random() < 0.5
                    continue
                else
                    token = token.slice(0, -1)
            synonym = root.get(token)
            if !synonym
                throw new Error 'No such synonym on root: ' + token

            pruned_synonym = synonym.prune(chosen_synonyms[token])

            # Reset chosen list if empty
            if pruned_synonym.children.length == 0
                pruned_synonym = synonym
                delete chosen_synonyms[token]

            chosen_synonym = pruned_synonym.randomLeaf().key

            # Add chosen to chosen list
            chosen_synonyms[token] ||= []
            chosen_synonyms[token].push chosen_synonym

            synonym_tokens = chosen_synonym.split(' ')
            expanded = expanded.concat expandTokens synonym_tokens, root, context

        # Hash (keyed value given what's in context)
        else if token.match /^#/
            [token, given...] = token.split('|')

            sub_phrase = root.get(token)
            if !sub_phrase?
                throw new Error 'No such hash on root: ' + token

            if !given.length
                throw new Error 'No values given for hash: ' + token

            for g in given
                if g.match /^\$/
                    sub_phrase = sub_phrase.get(context[g])
                else
                    sub_phrase = sub_phrase.get(g)
                if !sub_phrase?
                    throw new Error 'No such value on hash: ' +
                        token + '|' + given.map((g) -> context[g]).join('|')

            sub_tokens = sub_phrase.randomLeaf().key.split(' ')
            expanded = expanded.concat expandTokens sub_tokens, root, context

        # Regular word token
        else
            expanded.push token

    return expanded

module.exports.fromPlainString = (string, context) ->
    root = parse.fromObject {'%': string}
    generate root, context

# Run as a script
if require.main == module
    argv = minimist(process.argv.slice(2))
    parse = require './parse'

    filename = process.argv[2]
    if !filename?
        console.log "Usage: nalgene [file.nlg] (--key=value...)"
        process.exit()

    # Parse the gramamr file
    grammar = parse fs.readFileSync filename, 'utf8'

    # Build context from arguments
    context = {}
    for k, v of argv
        context['$' + k] =  v

    # Generate
    console.log generate grammar, context

