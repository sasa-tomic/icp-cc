#[cfg(test)]
mod tests {
    use crate::config::{AppConfig, AttributeType};
    use reqwest::Client;
    use std::time::Duration;

    fn create_test_db_manager() -> crate::database::DatabaseManager {
        let config = AppConfig {
            endpoint: "https://test.appwrite.io/v1".to_string(),
            project_id: "test-project".to_string(),
            api_key: "test-key".to_string(),
            database_id: "test-db".to_string(),
            scripts_collection_id: "test-scripts".to_string(),
            users_collection_id: "test-users".to_string(),
            purchases_collection_id: "test-purchases".to_string(),
            reviews_collection_id: "test-reviews".to_string(),
            storage_bucket_id: "test-bucket".to_string(),
        };

        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("Failed to create test HTTP client");

        crate::database::DatabaseManager { client, config }
    }

    #[test]
    fn test_scripts_attributes_includes_all_required_fields() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_scripts_attributes();

        // Convert to a set of attribute names for easier checking
        let attribute_names: std::collections::HashSet<String> = attributes
            .iter()
            .map(|(name, _, _, _, _)| name.to_string())
            .collect();

        // Test that all required fields are present
        assert!(attribute_names.contains("title"));
        assert!(attribute_names.contains("description"));
        assert!(attribute_names.contains("category"));
        assert!(attribute_names.contains("tags"));
        assert!(attribute_names.contains("authorId"));
        assert!(attribute_names.contains("authorName"));
        assert!(attribute_names.contains("price"));
        assert!(attribute_names.contains("downloads"));
        assert!(attribute_names.contains("rating"));
        assert!(attribute_names.contains("reviewCount"));
        assert!(attribute_names.contains("luaSource"));
        assert!(attribute_names.contains("iconUrl"));
        assert!(attribute_names.contains("screenshots"));
        assert!(attribute_names.contains("canisterIds"));
        assert!(attribute_names.contains("compatibility"));
        assert!(attribute_names.contains("version"));
        assert!(attribute_names.contains("isPublic"));
        assert!(attribute_names.contains("isApproved"));

        // Test the new fields we added
        assert!(attribute_names.contains("createdAt"));
        assert!(attribute_names.contains("updatedAt"));
        assert!(attribute_names.contains("isDeleted"));
    }

    #[test]
    fn test_scripts_attributes_have_correct_types() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_scripts_attributes();

        // Create a map for easy lookup
        let attribute_map: std::collections::HashMap<String, (AttributeType, Option<i32>, bool)> =
            attributes
                .iter()
                .map(|(name, attr_type, size, required, _)| {
                    (name.to_string(), (*attr_type, *size, *required))
                })
                .collect();

        // Test specific fields have correct types
        assert_eq!(attribute_map.get("title").unwrap().0, AttributeType::String);
        assert_eq!(
            attribute_map.get("description").unwrap().0,
            AttributeType::String
        );
        assert_eq!(attribute_map.get("price").unwrap().0, AttributeType::Float);
        assert_eq!(
            attribute_map.get("downloads").unwrap().0,
            AttributeType::Integer
        );
        assert_eq!(attribute_map.get("rating").unwrap().0, AttributeType::Float);
        assert_eq!(
            attribute_map.get("isPublic").unwrap().0,
            AttributeType::Boolean
        );
        assert_eq!(
            attribute_map.get("isApproved").unwrap().0,
            AttributeType::Boolean
        );
        assert_eq!(
            attribute_map.get("tags").unwrap().0,
            AttributeType::StringArray
        );
        assert_eq!(
            attribute_map.get("screenshots").unwrap().0,
            AttributeType::StringArray
        );
        assert_eq!(
            attribute_map.get("canisterIds").unwrap().0,
            AttributeType::StringArray
        );

        // Test new fields have correct types
        assert_eq!(
            attribute_map.get("createdAt").unwrap().0,
            AttributeType::Integer
        );
        assert_eq!(
            attribute_map.get("updatedAt").unwrap().0,
            AttributeType::Integer
        );
        assert_eq!(
            attribute_map.get("isDeleted").unwrap().0,
            AttributeType::Boolean
        );
    }

    #[test]
    fn test_scripts_attributes_have_correct_requirements() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_scripts_attributes();

        // Create a map for easy lookup
        let attribute_map: std::collections::HashMap<String, (AttributeType, Option<i32>, bool)> =
            attributes
                .iter()
                .map(|(name, attr_type, size, required, _)| {
                    (name.to_string(), (*attr_type, *size, *required))
                })
                .collect();

        // Test required fields
        assert!(attribute_map.get("title").unwrap().2); // title is required
        assert!(attribute_map.get("description").unwrap().2); // description is required
        assert!(attribute_map.get("luaSource").unwrap().2); // luaSource is required

        // Test optional fields
        assert!(!attribute_map.get("price").unwrap().2); // price is optional
        assert!(!attribute_map.get("downloads").unwrap().2); // downloads is optional
        assert!(!attribute_map.get("rating").unwrap().2); // rating is optional
        assert!(!attribute_map.get("createdAt").unwrap().2); // createdAt is optional (has default)
        assert!(!attribute_map.get("updatedAt").unwrap().2); // updatedAt is optional (has default)
        assert!(!attribute_map.get("isDeleted").unwrap().2); // isDeleted is optional (has default)
    }

    #[test]
    fn test_users_attributes_includes_all_required_fields() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_users_attributes();

        // Convert to a set of attribute names for easier checking
        let attribute_names: std::collections::HashSet<String> = attributes
            .iter()
            .map(|(name, _, _, _, _)| name.to_string())
            .collect();

        // Test that all user fields are present
        assert!(attribute_names.contains("userId"));
        assert!(attribute_names.contains("username"));
        assert!(attribute_names.contains("displayName"));
        assert!(attribute_names.contains("bio"));
        assert!(attribute_names.contains("avatar"));
        assert!(attribute_names.contains("website"));
        assert!(attribute_names.contains("socialLinks"));
        assert!(attribute_names.contains("scriptsPublished"));
        assert!(attribute_names.contains("totalDownloads"));
        assert!(attribute_names.contains("averageRating"));
        assert!(attribute_names.contains("isVerifiedDeveloper"));
        assert!(attribute_names.contains("favorites"));
    }

    #[test]
    fn test_users_attributes_have_correct_types() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_users_attributes();

        // Create a map for easy lookup
        let attribute_map: std::collections::HashMap<String, AttributeType> = attributes
            .iter()
            .map(|(name, attr_type, _, _, _)| (name.to_string(), *attr_type))
            .collect();

        // Test specific fields have correct types
        assert_eq!(attribute_map.get("userId").unwrap(), &AttributeType::String);
        assert_eq!(
            attribute_map.get("username").unwrap(),
            &AttributeType::String
        );
        assert_eq!(
            attribute_map.get("displayName").unwrap(),
            &AttributeType::String
        );
        assert_eq!(
            attribute_map.get("scriptsPublished").unwrap(),
            &AttributeType::Integer
        );
        assert_eq!(
            attribute_map.get("totalDownloads").unwrap(),
            &AttributeType::Integer
        );
        assert_eq!(
            attribute_map.get("averageRating").unwrap(),
            &AttributeType::Float
        );
        assert_eq!(
            attribute_map.get("isVerifiedDeveloper").unwrap(),
            &AttributeType::Boolean
        );
        assert_eq!(
            attribute_map.get("socialLinks").unwrap(),
            &AttributeType::StringArray
        );
        assert_eq!(
            attribute_map.get("favorites").unwrap(),
            &AttributeType::StringArray
        );
    }

    #[test]
    fn test_reviews_attributes_includes_all_required_fields() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_reviews_attributes();

        // Convert to a set of attribute names for easier checking
        let attribute_names: std::collections::HashSet<String> = attributes
            .iter()
            .map(|(name, _, _, _, _)| name.to_string())
            .collect();

        // Test that all review fields are present
        assert!(attribute_names.contains("userId"));
        assert!(attribute_names.contains("scriptId"));
        assert!(attribute_names.contains("rating"));
        assert!(attribute_names.contains("comment"));
        assert!(attribute_names.contains("isVerifiedPurchase"));
        assert!(attribute_names.contains("status"));
    }

    #[test]
    fn test_reviews_attributes_have_correct_types() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_reviews_attributes();

        // Create a map for easy lookup
        let attribute_map: std::collections::HashMap<String, AttributeType> = attributes
            .iter()
            .map(|(name, attr_type, _, _, _)| (name.to_string(), *attr_type))
            .collect();

        // Test specific fields have correct types
        assert_eq!(attribute_map.get("userId").unwrap(), &AttributeType::String);
        assert_eq!(
            attribute_map.get("scriptId").unwrap(),
            &AttributeType::String
        );
        assert_eq!(
            attribute_map.get("rating").unwrap(),
            &AttributeType::Integer
        );
        assert_eq!(
            attribute_map.get("comment").unwrap(),
            &AttributeType::String
        );
        assert_eq!(
            attribute_map.get("isVerifiedPurchase").unwrap(),
            &AttributeType::Boolean
        );
        assert_eq!(attribute_map.get("status").unwrap(), &AttributeType::String);
    }

    #[test]
    fn test_purchases_attributes_includes_all_required_fields() {
        let db_manager = create_test_db_manager();
        let attributes = db_manager.get_purchases_attributes();

        // Convert to a set of attribute names for easier checking
        let attribute_names: std::collections::HashSet<String> = attributes
            .iter()
            .map(|(name, _, _, _, _)| name.to_string())
            .collect();

        // Test that all purchase fields are present
        assert!(attribute_names.contains("userId"));
        assert!(attribute_names.contains("scriptId"));
        assert!(attribute_names.contains("transactionId"));
        assert!(attribute_names.contains("price"));
        assert!(attribute_names.contains("currency"));
        assert!(attribute_names.contains("status"));
        assert!(attribute_names.contains("paymentMethod"));
    }

    #[test]
    fn test_collection_names_are_unique() {
        let db_manager = create_test_db_manager();
        let scripts_collection = db_manager.config.scripts_collection_id.clone();
        let users_collection = db_manager.config.users_collection_id.clone();
        let reviews_collection = db_manager.config.reviews_collection_id.clone();
        let purchases_collection = db_manager.config.purchases_collection_id.clone();

        // Ensure all collection names are different
        assert_ne!(scripts_collection, users_collection);
        assert_ne!(scripts_collection, reviews_collection);
        assert_ne!(scripts_collection, purchases_collection);
        assert_ne!(users_collection, reviews_collection);
        assert_ne!(users_collection, purchases_collection);
        assert_ne!(reviews_collection, purchases_collection);
    }
}
