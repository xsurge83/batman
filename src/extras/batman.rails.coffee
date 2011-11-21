Batman.mixin Batman.Encoders,
  railsDate:
    encode: (value) -> value
    decode: (value) ->
      a = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}(?:\.\d*)?)Z$/.exec(value)
      if a
        return new Date(Date.UTC(+a[1], +a[2] - 1, +a[3], +a[4], +a[5], +a[6]))
      else
        Batman.developer.warn "Unrecognized rails date #{value}!"
        return Date.parse(value)

class Batman.RailsStorage extends Batman.RestStorage

  _addJsonExtension: (options) ->
    options.url += '.json'

  _prepareForAssociation: (modelClass, options, recordOptions) ->
    association = id = null
    if belongTos = modelClass._batman.associations?.getByType('belongsTo')
      # Find a belongsTo with a localKey that is being requested
      # TODO AssociationCollection should extend Set to allow indexing by localKey
      belongTos.forEach (belongsTo) ->
        if id = recordOptions[belongsTo.localKey]
          association = belongsTo

      if association and inverse = association.inverse()
        if inverse.isSingular
          @_prepareForSingularAssociation(association, id, options, recordOptions)
        else if inverse.isPlural
          @_prepareForPluralAssociation(association, id, options, recordOptions)

        # Delete localKey to stop RestStorage from appending "?store_id=1"
        delete options.data[association.localKey]
        delete recordOptions[association.localKey]
  
  _prepareForSingularAssociation: (association, id, options, recordOptions) ->
    root = Batman.helpers.pluralize(association.label)
    ending = Batman.helpers.singularize(options.url.substr(1))
    options.url = "/#{root}/#{id}/#{ending}"

  _prepareForPluralAssociation: (association, id, options, recordOptions) ->
    root = Batman.helpers.pluralize(association.label)
    ending = Batman.helpers.pluralize(options.url.substr(1))
    options.url = "/#{root}/#{id}/#{ending}"

  optionsForRecord: (args..., callback) ->
    super args..., (err, options) ->
      unless err
        @_addJsonExtension(options)
      callback.call @, err, options

  optionsForCollection: (modelClass, recordOptions, callback) ->
    super modelClass, recordOptions, (err, options) ->
      unless err
        @_prepareForAssociation(modelClass, options, recordOptions)
        @_addJsonExtension(options)
      callback.call @, err, options

  @::after 'update', 'create', ([err, record, response, recordOptions]) ->
    # Rails validation errors
    if err
      if err.request.get('status') is 422
        for key, validationErrors of JSON.parse(err.request.get('response'))
          record.get('errors').add(key, "#{key} #{validationError}") for validationError in validationErrors
        return [record.get('errors'), record, response, recordOptions]
    return arguments[0]
