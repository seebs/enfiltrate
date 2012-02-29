LibEnfiltrate is a generic filtering tool intended to work with the common
result format of Inspect.*.Detail.

A filter consists of three classes of things; inclusions, requirements,
and exclusions.  It also has a 'type', which is sort of sporadically used;
the intent is that type will cause things like special rules for processing
known fields of items, for instance.

In general, a filter operates on a set of items.  The result is a new
set of items containing only those items which "match" a filter.  An
item matches if:

* It matches all requirements.
* It does not match any exclusions.
* Either it matches at least one inclusion, or there are no inclusions.

Thus, an empty filter contains all the items in its input set.

Each matcher may be one of the following things:

1.  A function.
	To permit saving and loading of representations, functions are
	actually passed in as strings.  Your code will be parsed as
		local item = ...; <YOUR CODE HERE>
	so refer to the item table for matching.

	If you have an existing function you want to call, you can
	call it; try something like
		return MyAddon.MyFunc(item)


2.  A relation.

	A relation is a table:
	    { field = fieldname, relation = relop, value = something }

	For instance, the relation
	    { field = "stack", relation = ">", value = 3 }
        matches any item which has a .stack member which compares
	greater than 3.

	Which members are meaningful depends on the category.  In theory,
	type information will be getting added for various categories.


FILTER OPS:
	filter:save()
		Stores in SavedVariables.  Note that the 'addon'
		tag provided when creating the filter provides a
		separate namespace for each key.
	filter:delete()
		Deletes filter from SavedVariables.  If it was
		a LibEnfiltrate filter, rather than one for another
		addon, also deletes it from the internal table.
	filter:dump()
		Pretty self-explanatory.

	filter:include(matchable, verbose)
	filter:exclude(matchable, verbose)
	filter:require(matchable, verbose)
		Add "matchable" to the given category.

	filter:disinclude(index, verbose)
	filter:disexclude(index, verbose)
	filter:disrequire(index, verbose)
		Remove item index from the given category.

	filter:filter(table)
		Returns a table of items which matched the
		filter, preserving their keys.
	filter:match(item)
		Indicates whether the given item matches the
		filter.

	Library.LibEnfiltrate.Filter:new(name, addon, type)
		addon defaults to 'LibEnfiltrate'
		type defaults to 'generic'

	Library.LibEnfiltrate.Filter:from_representation(table)
		Recreates a filter from the given representation table.

	Library.LibEnfiltrate.Filter:load(name, addon)
		Load the named item from the stored filters
		for the given addon.
		addon defaults to 'LibEnfiltrate'


SLASH COMMAND:
	/enfilt [opts]
		-i <condition>:  add to includes
		-x <condition>:  add to excludes
		-r <condition>:  add to requires
		-I <index>:  remove from includes
		-X <index>:  remove from excludes
		-R <index>:  remove from requires
		-d: dump
		-D: delete
		-f <name>:  select named filter
		-a <addon>:  use addon's filter namespace
		-z:  Run on Inspect.Item.Detail(inventory)
		-c <category>:  use named category (only "item" works)
		-v:  print version info

COMING IN THE FUTURE:
	More logic for various categories.

	Might allow plain functions to be passed in, but they won't
	survive save/load pairs.
