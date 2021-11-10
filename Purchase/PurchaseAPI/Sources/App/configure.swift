import Fluent
import FluentPostgresDriver
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(.postgres(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? PostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "mac",
        password: Environment.get("DATABASE_PASSWORD") ?? "",
        database: Environment.get("DATABASE_NAME") ?? "Purchase"
    ), as: .psql)

    app.migrations.add(DepartamentMigration())
    app.migrations.add(MeasureUnitMigration())
    app.migrations.add(ProviderMigration())
    app.migrations.add(ArticleMigration())
    app.migrations.add(PurchaseOrderMigration())
    
    //try app.autoRevert().wait()
    
    //try app.autoMigrate().wait()
    
    // register routes
    try routes(app)
}
