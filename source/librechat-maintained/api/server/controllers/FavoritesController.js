const { updateUser, getUserById, getAgents } = require('~/models');
const {
  findAccessibleResources,
  findPubliclyAccessibleResources,
} = require('~/server/services/PermissionService');
const { PermissionBits, ResourceType } = require('librechat-data-provider');

const MAX_FAVORITES = 50;
const MAX_STRING_LENGTH = 256;

const updateFavoritesController = async (req, res) => {
  try {
    const { favorites } = req.body;
    const userId = req.user.id;

    if (!favorites) {
      return res.status(400).json({ message: 'Favorites data is required' });
    }

    if (!Array.isArray(favorites)) {
      return res.status(400).json({ message: 'Favorites must be an array' });
    }

    if (favorites.length > MAX_FAVORITES) {
      return res.status(400).json({
        code: 'MAX_FAVORITES_EXCEEDED',
        message: `Maximum ${MAX_FAVORITES} favorites allowed`,
        limit: MAX_FAVORITES,
      });
    }

    for (const fav of favorites) {
      const hasAgent = !!fav.agentId;
      const hasModel = !!(fav.model && fav.endpoint);
      const hasSpec = !!fav.spec;

      if (fav.agentId && fav.agentId.length > MAX_STRING_LENGTH) {
        return res
          .status(400)
          .json({ message: `agentId exceeds maximum length of ${MAX_STRING_LENGTH}` });
      }
      if (fav.model && fav.model.length > MAX_STRING_LENGTH) {
        return res
          .status(400)
          .json({ message: `model exceeds maximum length of ${MAX_STRING_LENGTH}` });
      }
      if (fav.endpoint && fav.endpoint.length > MAX_STRING_LENGTH) {
        return res
          .status(400)
          .json({ message: `endpoint exceeds maximum length of ${MAX_STRING_LENGTH}` });
      }
      if (fav.spec !== undefined && fav.spec !== null) {
        if (typeof fav.spec !== 'string' || fav.spec.length === 0) {
          return res.status(400).json({ message: 'spec must be a non-empty string' });
        }
        if (fav.spec.length > MAX_STRING_LENGTH) {
          return res
            .status(400)
            .json({ message: `spec exceeds maximum length of ${MAX_STRING_LENGTH}` });
        }
      }

      const hasPartialModel = !hasModel && !!(fav.model || fav.endpoint);

      if (hasPartialModel && !hasAgent && !hasSpec) {
        return res.status(400).json({ message: 'model and endpoint must be provided together' });
      }

      const typeCount = [hasAgent, hasModel, hasSpec].filter(Boolean).length;
      if (typeCount === 0) {
        return res.status(400).json({
          message: 'Each favorite must have either agentId, model+endpoint, or spec',
        });
      }

      if (typeCount > 1) {
        return res.status(400).json({
          message: 'Favorite cannot have multiple types (agentId, model/endpoint, or spec)',
        });
      }

      if (hasSpec && (fav.agentId || fav.model || fav.endpoint)) {
        return res
          .status(400)
          .json({ message: 'spec cannot be combined with agentId, model, or endpoint' });
      }
      if (hasAgent && (fav.model || fav.endpoint)) {
        return res
          .status(400)
          .json({ message: 'agentId cannot be combined with model or endpoint' });
      }
    }

    const agentIds = favorites
      .filter((favorite) => !!favorite.agentId)
      .map((favorite) => favorite.agentId);
    if (agentIds.length > 0) {
      const [agents, accessibleIds, publicIds] = await Promise.all([
        getAgents({ id: { $in: agentIds } }),
        findAccessibleResources({
          userId,
          role: req.user.role,
          resourceType: ResourceType.AGENT,
          requiredPermissions: PermissionBits.VIEW,
        }),
        findPubliclyAccessibleResources({
          resourceType: ResourceType.AGENT,
          requiredPermissions: PermissionBits.VIEW,
        }),
      ]);
      const permittedObjectIds = new Set(
        [...(accessibleIds ?? []), ...(publicIds ?? [])].map((id) => id.toString()),
      );
      const permittedAgentIds = new Set(
        (agents ?? [])
          .filter((agent) => agent?._id && permittedObjectIds.has(agent._id.toString()))
          .map((agent) => agent.id),
      );
      const unauthorizedAgentIds = [...new Set(agentIds)].filter(
        (agentId) => !permittedAgentIds.has(agentId),
      );
      if (unauthorizedAgentIds.length > 0) {
        return res.status(403).json({
          code: 'AGENT_VIEW_REQUIRED',
          message: 'You can only favorite Agents you are authorized to view.',
          agent_ids: unauthorizedAgentIds,
        });
      }
    }

    const user = await updateUser(userId, { favorites });

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    return res.status(200).json(user.favorites);
  } catch (error) {
    console.error('Error updating favorites:', error);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

const getFavoritesController = async (req, res) => {
  try {
    const userId = req.user.id;
    const user = await getUserById(userId, 'favorites');

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    let favorites = user.favorites || [];

    if (!Array.isArray(favorites)) {
      favorites = [];
      await updateUser(userId, { favorites: [] });
    }

    return res.status(200).json(favorites);
  } catch (error) {
    console.error('Error fetching favorites:', error);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

module.exports = {
  updateFavoritesController,
  getFavoritesController,
};
