var cacheConfigSchema = undefined

exports.getConfigSchema = function getConfigSchema(callback) {
  if (cacheConfigSchema) return callback(cacheConfigSchema)
  atom.packages.activatePackage('todog').then( () => {
    cacheConfigSchema = atom.config.getSchema('todog').properties
    callback(cacheConfigSchema)
  })
}
